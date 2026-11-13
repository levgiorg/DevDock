package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var idPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

func validID(id string) bool { return idPattern.MatchString(id) }
func validAction(action string) bool {
	switch action {
	case "start", "stop", "restart", "pause", "unpause":
		return true
	}
	return false
}

type binding struct {
	HostIP   string `json:"HostIp"`
	HostPort string `json:"HostPort"`
}
type inspection struct {
	ID    string `json:"Id"`
	Name  string `json:"Name"`
	State struct {
		Running bool
		Paused  bool
		Status  string
	} `json:"State"`
	HostConfig struct{ PortBindings map[string][]binding } `json:"HostConfig"`
}

func (i inspection) portStrings() []string {
	result := []string{}
	for internal, bindings := range i.HostConfig.PortBindings {
		port, protocol, ok := strings.Cut(internal, "/")
		if !ok || protocol != "tcp" {
			continue
		}
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			continue
		}
		for _, b := range bindings {
			p, err := strconv.Atoi(b.HostPort)
			if err != nil || p < 1 || p > 65535 {
				continue
			}
			ip := b.HostIP
			if ip == "" {
				ip = "0.0.0.0"
			}
			if net.ParseIP(ip) == nil {
				continue
			}
			result = append(result, fmt.Sprintf("%s -> %d/tcp", net.JoinHostPort(ip, strconv.Itoa(p)), n))
		}
	}
	sort.Strings(result)
	return result
}

type container struct {
	ID    string   `json:"id"`
	Name  string   `json:"name"`
	Image string   `json:"image"`
	State string   `json:"state"`
	Ports []string `json:"ports"`
}
type docker struct {
	http      *http.Client
	transport *http.Transport
}

func trustedSocket(path string) bool {
	if !filepath.IsAbs(path) || strings.ContainsRune(path, 0) {
		return false
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode()&os.ModeSocket == 0 {
		return false
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && (stat.Uid == uint32(os.Getuid()) || stat.Uid == 0)
}
func discoverSocket() string {
	home, _ := os.UserHomeDir()
	for _, path := range []string{fmt.Sprintf("/run/user/%d/docker.sock", os.Getuid()), filepath.Join(home, ".docker/run/docker.sock"), "/var/run/docker.sock"} {
		if trustedSocket(path) {
			return path
		}
	}
	return ""
}
func newDocker(socket string) *docker {
	transport := &http.Transport{Proxy: nil, MaxConnsPerHost: 2, MaxIdleConnsPerHost: 1, MaxResponseHeaderBytes: 16 * 1024, ResponseHeaderTimeout: 15 * time.Second, DisableCompression: true,
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			if !trustedSocket(socket) {
				return nil, errors.New("untrusted local Docker socket")
			}
			return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, "unix", socket)
		}}
	return &docker{&http.Client{Transport: transport, Timeout: 18 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, transport}
}
func (d *docker) close() { d.transport.CloseIdleConnections() }
func allowedRequest(method, path string) bool {
	if method == "GET" && path == "/containers/json?all=1" {
		return true
	}
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
	if len(parts) != 3 || parts[0] != "containers" || !validID(parts[1]) {
		return false
	}
	if method == "GET" {
		return parts[2] == "json"
	}
	action := strings.TrimSuffix(parts[2], "?t=10")
	return method == "POST" && validAction(action) && (parts[2] == action || ((action == "stop" || action == "restart") && parts[2] == action+"?t=10"))
}
func (d *docker) request(ctx context.Context, method, path string, target any) error {
	if !allowedRequest(method, path) {
		return errors.New("Docker endpoint is not allowed")
	}
	req, err := http.NewRequestWithContext(ctx, method, "http://docker"+path, nil)
	if err != nil {
		return err
	}
	response, err := d.http.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	const max = 8 * 1024 * 1024
	body, err := io.ReadAll(io.LimitReader(response.Body, max+1))
	if err != nil {
		return err
	}
	if len(body) > max {
		return errors.New("Docker response exceeds limit")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("Docker returned HTTP %d", response.StatusCode)
	}
	if target != nil {
		return json.Unmarshal(body, target)
	}
	return nil
}
func (d *docker) inspect(ctx context.Context, id string) (inspection, error) {
	var i inspection
	if !validID(id) {
		return i, errors.New("invalid full container ID")
	}
	err := d.request(ctx, "GET", "/containers/"+id+"/json", &i)
	if err == nil && (i.ID != id || !strings.HasPrefix(i.Name, "/")) {
		err = errors.New("container identity changed or is incomplete")
	}
	return i, err
}
func allowedState(action string, i inspection) bool {
	switch action {
	case "start":
		return !i.State.Running
	case "stop", "restart":
		return i.State.Running
	case "pause":
		return i.State.Running && !i.State.Paused
	case "unpause":
		return i.State.Running && i.State.Paused
	}
	return false
}
func (d *docker) perform(ctx context.Context, action string, expected inspection) error {
	if !validAction(action) || !validID(expected.ID) {
		return errors.New("invalid Docker action target")
	}
	current, err := d.inspect(ctx, expected.ID)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(current, expected) || !allowedState(action, current) {
		return errors.New("container identity, state or port mappings changed; refresh before acting")
	}
	path := "/containers/" + current.ID + "/" + action
	if action == "stop" || action == "restart" {
		path += "?t=10"
	}
	return d.request(ctx, "POST", path, nil)
}
func (d *docker) list(ctx context.Context) ([]container, error) {
	var raw []struct {
		ID    string `json:"Id"`
		Names []string
		Image string
		State string
		Ports []struct {
			IP          string
			PrivatePort int
			PublicPort  int
			Type        string
		}
	}
	if err := d.request(ctx, "GET", "/containers/json?all=1", &raw); err != nil {
		return nil, err
	}
	if len(raw) > 512 {
		return nil, errors.New("Docker listing exceeds 512-container safety limit")
	}
	result := []container{}
	for _, r := range raw {
		if !validID(r.ID) {
			return nil, errors.New("Docker returned an invalid container ID")
		}
		c := container{ID: r.ID, Image: r.Image, State: r.State, Ports: []string{}}
		if len(r.Names) > 0 {
			c.Name = strings.TrimPrefix(r.Names[0], "/")
		}
		for _, p := range r.Ports {
			if p.Type == "tcp" && p.PublicPort > 0 && p.PublicPort < 65536 && p.PrivatePort > 0 && p.PrivatePort < 65536 {
				ip := p.IP
				if ip == "" {
					ip = "0.0.0.0"
				}
				if net.ParseIP(ip) != nil {
					c.Ports = append(c.Ports, fmt.Sprintf("%s -> %d/tcp", net.JoinHostPort(ip, strconv.Itoa(p.PublicPort)), p.PrivatePort))
				}
			}
		}
		if c.State != "running" && c.State != "paused" {
			i, err := d.inspect(ctx, c.ID)
			if err != nil {
				return nil, err
			}
			c.Ports = i.portStrings()
		}
		sort.Strings(c.Ports)
		result = append(result, c)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result, nil
}
