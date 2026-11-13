package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestTCPParsing(t *testing.T) {
	data := []byte("0: 0100007F:1F90 00000000:0000 0A 0:0 0:0 0 1000 0 42\n1: 00000000000000000000000001000000:01BB 0:0 0A 0:0 0:0 0 1000 0 43\n2: 0100007F:1F90 0:0 01 0:0 0:0 0 1000 0 44")
	got := parseTCP(data, 1000)
	if len(got) != 2 || got[0].address != "127.0.0.1" || got[0].port != 8080 || got[1].address != "::1" {
		t.Fatalf("unexpected sockets: %+v", got)
	}
	if len(parseTCP(data, 1001)) != 0 {
		t.Fatal("cross-user socket leaked")
	}
	for _, value := range []string{"bad", "GG:1234", "0100007F:10000", "0100007F:0"} {
		if _, _, err := decodeAddress(value); err == nil {
			t.Fatal(value)
		}
	}
}
func TestStartTicksHandlesParentheses(t *testing.T) {
	value := "12 (server ) with spaces) S " + strings.Repeat("0 ", 18) + "123 0"
	if startTicks([]byte(value)) != "123" {
		t.Fatal(startTicks([]byte(value)))
	}
	if startTicks([]byte("bad")) != "" {
		t.Fatal("malformed stat accepted")
	}
}
func TestBoundedReadsAndWorktree(t *testing.T) {
	root := t.TempDir()
	p := filepath.Join(root, "file")
	if err := os.WriteFile(p, []byte("1234"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readBounded(p, 2); err == nil {
		t.Fatal("oversize accepted")
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(p, link); err != nil {
		t.Fatal(err)
	}
	if _, err := readBounded(link, 8); err == nil {
		t.Fatal("symlink accepted")
	}
	fifo := filepath.Join(root, "fifo")
	if err := syscall.Mkfifo(fifo, 0600); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	if _, err := readBounded(fifo, 8); err == nil || time.Since(start) > time.Second {
		t.Fatal("FIFO did not fail promptly")
	}
	git := filepath.Join(root, "worktree-meta")
	if err := os.Mkdir(git, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(git, "HEAD"), []byte("ref: refs/heads/feature/linux\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".git"), []byte("gitdir: worktree-meta\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if branchFor(root) != "feature/linux" {
		t.Fatal("worktree branch missing")
	}
}
func TestTerminalAndCLI(t *testing.T) {
	if clean("name\x1b]52;secret\n\u202eevil") != "name]52;secretevil" {
		t.Fatal("unsafe terminal controls")
	}
	var out, errs bytes.Buffer
	if err := run([]string{"--version"}, strings.NewReader(""), &out, &errs); err != nil || !strings.Contains(out.String(), "DevDock") {
		t.Fatal(err)
	}
	if err := run([]string{"--help"}, strings.NewReader(""), &out, &errs); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"docker", "stop", "../wrong"}, strings.NewReader(""), &out, &errs); err == nil {
		t.Fatal("invalid identity accepted")
	}
}
func TestRealLinuxListenerIsReadOnly(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("real /proc integration requires Linux")
	}
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	port := l.Addr().(*net.TCPAddr).Port
	processes, warnings := scanProcesses("/proc", uint32(os.Getuid()))
	found := false
	for _, p := range processes {
		if p.PID == os.Getpid() && p.Port == port {
			found = p.StartTicks != "" && p.Executable != ""
		}
	}
	if !found {
		t.Fatalf("own listener not found: %v", warnings)
	}
	c, err := net.DialTimeout("tcp", l.Addr().String(), time.Second)
	if err != nil {
		t.Fatal("inspection interfered with listener:", err)
	}
	c.Close()
}
func fakeDocker(t *testing.T, handler http.HandlerFunc) *docker {
	t.Helper()
	directory, err := os.MkdirTemp("/tmp", "devdock-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socket := filepath.Join(directory, "docker.sock")
	l, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: time.Second}
	go func() { _ = server.Serve(l) }()
	d := newDocker(socket)
	t.Cleanup(func() { d.close(); _ = server.Close() })
	return d
}
func TestDockerFreshIdentityAndState(t *testing.T) {
	id := strings.Repeat("a", 64)
	current := inspection{ID: id, Name: "/fixture"}
	current.State.Running = true
	current.State.Status = "running"
	current.HostConfig.PortBindings = map[string][]binding{"8080/tcp": {{"127.0.0.1", "34567"}}}
	expected := current
	posts := 0
	d := fakeDocker(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" {
			_ = json.NewEncoder(w).Encode(current)
		} else {
			posts++
			if r.URL.RequestURI() != "/containers/"+id+"/stop?t=10" {
				t.Errorf("unexpected endpoint %s", r.URL)
			}
			w.WriteHeader(204)
		}
	})
	if err := d.perform(context.Background(), "stop", expected); err != nil {
		t.Fatal(err)
	}
	if posts != 1 {
		t.Fatal(posts)
	}
	current.Name = "/renamed"
	if err := d.perform(context.Background(), "stop", expected); err == nil || posts != 1 {
		t.Fatal("stale identity allowed")
	}
	current = expected
	current.HostConfig.PortBindings = map[string][]binding{"8080/tcp": {{"127.0.0.1", "34568"}}}
	if err := d.perform(context.Background(), "stop", expected); err == nil || posts != 1 {
		t.Fatal("stale port mappings allowed")
	}
	current = expected
	current.State.Running = false
	if err := d.perform(context.Background(), "stop", expected); err == nil || posts != 1 {
		t.Fatal("stale state allowed")
	}
	for _, id := range []string{"abc", "../other", strings.Repeat("A", 64)} {
		if validID(id) {
			t.Fatal(id)
		}
	}
	for _, path := range []string{"/containers/create", "/containers/../stop", "/containers/" + id + "/kill", "/info\r\nInjected: true"} {
		if allowedRequest("POST", path) {
			t.Fatal(path)
		}
	}
}
func TestDockerMalformedAndStoppedMappings(t *testing.T) {
	id := strings.Repeat("b", 64)
	i := inspection{ID: id, Name: "/stopped"}
	i.HostConfig.PortBindings = map[string][]binding{"80/tcp": {{"127.0.0.1", "34567"}}, "53/udp": {{"", "53"}}, "90/tcp": {{"bad-ip", "bad"}}}
	d := fakeDocker(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/containers/json" {
			fmt.Fprintf(w, `[{"Id":%q,"Names":["/stopped"],"State":"exited"}]`, id)
		} else {
			_ = json.NewEncoder(w).Encode(i)
		}
	})
	got, err := d.list(context.Background())
	if err != nil || len(got) != 1 || len(got[0].Ports) != 1 || got[0].Ports[0] != "127.0.0.1:34567 -> 80/tcp" {
		t.Fatalf("%+v %v", got, err)
	}
	malformed := fakeDocker(t, func(w http.ResponseWriter, r *http.Request) { _, _ = io.WriteString(w, "not JSON") })
	if _, err := malformed.list(context.Background()); err == nil {
		t.Fatal("malformed JSON accepted")
	}
	if trustedSocket("tcp://localhost:2375") || trustedSocket(filepath.Join(t.TempDir(), "missing")) {
		t.Fatal("non-socket accepted")
	}
}
func TestDockerActualLifecycle(t *testing.T) {
	id := os.Getenv("DEVDOCK_TEST_CONTAINER")
	sentinel := os.Getenv("DEVDOCK_TEST_SENTINEL")
	if id == "" || sentinel == "" {
		t.Skip("requires uniquely labeled CI fixtures")
	}
	if !validID(id) || !validID(sentinel) || id == sentinel {
		t.Fatal("invalid fixture IDs")
	}
	d := newDocker("/var/run/docker.sock")
	defer d.close()
	for _, action := range []string{"pause", "unpause", "restart", "stop", "start"} {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		before, err := d.inspect(ctx, id)
		if err != nil {
			cancel()
			t.Fatal(err)
		}
		if err = d.perform(ctx, action, before); err != nil {
			cancel()
			t.Fatal(action, err)
		}
		alive, err := d.inspect(ctx, sentinel)
		cancel()
		if err != nil || !alive.State.Running {
			t.Fatal("sibling fixture affected", err)
		}
	}
}
func TestProcessFixture(t *testing.T) {
	root := t.TempDir()
	base := filepath.Join(root, strconv.Itoa(os.Getpid()))
	if err := os.MkdirAll(filepath.Join(base, "fd"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(root, "net"), 0700); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{"net/tcp": fmt.Sprintf("0: 0100007F:1F90 0:0 0A 0:0 0:0 0 %d 0 42\n", os.Getuid()), "net/tcp6": "", "" + strconv.Itoa(os.Getpid()) + "/stat": fmt.Sprintf("%d (fixture) S %s123 0", os.Getpid(), strings.Repeat("0 ", 18)), strconv.Itoa(os.Getpid()) + "/comm": "fixture\n", strconv.Itoa(os.Getpid()) + "/status": "VmRSS:\t42 kB\n"}
	for name, data := range files {
		if err := os.WriteFile(filepath.Join(root, name), []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	for name, target := range map[string]string{"fd/3": "socket:[42]", "exe": "/fixture", "cwd": root} {
		if err := os.Symlink(target, filepath.Join(base, name)); err != nil {
			t.Fatal(err)
		}
	}
	got, _ := scanProcesses(root, uint32(os.Getuid()))
	if len(got) != 1 || got[0].MemoryBytes != 42*1024 || got[0].Port != 8080 {
		t.Fatalf("%+v", got)
	}
}

func TestDockerBoundsRedirectsAndDeadline(t *testing.T) {
	for name, handler := range map[string]http.HandlerFunc{
		"body": func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.WriteString(w, strings.Repeat("x", 8*1024*1024+1))
		},
		"header": func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Oversized", strings.Repeat("x", 32768))
			_, _ = io.WriteString(w, "[]")
		},
		"redirect": func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "https://example.invalid/", http.StatusFound)
		},
		"deadline": func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() },
	} {
		t.Run(name, func(t *testing.T) {
			d := fakeDocker(t, handler)
			ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
			defer cancel()
			started := time.Now()
			if _, err := d.list(ctx); err == nil {
				t.Fatal("unsafe response accepted")
			}
			if time.Since(started) > 2*time.Second {
				t.Fatal("request exceeded deadline")
			}
		})
	}
}
