package main

import (
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

type listener struct {
	Port        int    `json:"port"`
	Address     string `json:"address"`
	PID         int    `json:"pid"`
	Name        string `json:"name"`
	Executable  string `json:"executable"`
	Directory   string `json:"directory"`
	Branch      string `json:"branch,omitempty"`
	StartTicks  string `json:"startTicks"`
	MemoryBytes uint64 `json:"memoryBytes"`
}
type socket struct {
	port           int
	address, inode string
}

// Nonblocking, no-follow reads prevent project metadata from turning into
// unbounded reads or blocking on a FIFO. /proc regular files report size zero.
func readBounded(path string, limit int64) ([]byte, error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("not a regular file")
	}
	b, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, fmt.Errorf("file exceeds read limit")
	}
	return b, nil
}
func decodeAddress(value string) (string, int, error) {
	host, portHex, ok := strings.Cut(value, ":")
	if !ok {
		return "", 0, fmt.Errorf("invalid address")
	}
	raw, err := hex.DecodeString(host)
	if err != nil || (len(raw) != 4 && len(raw) != 16) {
		return "", 0, fmt.Errorf("invalid address bytes")
	}
	for base := 0; base < len(raw); base += 4 {
		raw[base], raw[base+3] = raw[base+3], raw[base]
		raw[base+1], raw[base+2] = raw[base+2], raw[base+1]
	}
	port, err := strconv.ParseUint(portHex, 16, 16)
	if err != nil || port == 0 {
		return "", 0, fmt.Errorf("invalid port")
	}
	return net.IP(raw).String(), int(port), nil
}
func parseTCP(data []byte, uid uint32) []socket {
	result := []socket{}
	for _, line := range strings.Split(string(data), "\n") {
		f := strings.Fields(line)
		if len(f) < 10 || f[3] != "0A" {
			continue
		}
		owner, err := strconv.ParseUint(f[7], 10, 32)
		if err != nil || uint32(owner) != uid {
			continue
		}
		address, port, err := decodeAddress(f[1])
		if err != nil {
			continue
		}
		if _, err = strconv.ParseUint(f[9], 10, 64); err != nil || f[9] == "0" {
			continue
		}
		result = append(result, socket{port, address, f[9]})
	}
	return result
}
func startTicks(data []byte) string {
	// comm is parenthesized and may itself contain spaces or ')'.
	end := strings.LastIndex(string(data), ") ")
	if end < 0 {
		return ""
	}
	f := strings.Fields(string(data[end+2:]))
	if len(f) <= 19 {
		return ""
	}
	if _, err := strconv.ParseUint(f[19], 10, 64); err != nil {
		return ""
	}
	return f[19]
}
func branchFor(directory string) string {
	current := directory
	for depth := 0; depth < 32 && current != ""; depth++ {
		git := filepath.Join(current, ".git")
		if info, err := os.Lstat(git); err == nil {
			if info.IsDir() {
				data, err := readBounded(filepath.Join(git, "HEAD"), 32768)
				if err == nil {
					return branchName(data)
				}
				return ""
			}
			data, err := readBounded(git, 32768)
			if err != nil {
				return ""
			}
			pointer := strings.TrimSpace(strings.TrimPrefix(string(data), "gitdir: "))
			if !strings.HasPrefix(string(data), "gitdir: ") {
				return ""
			}
			if !filepath.IsAbs(pointer) {
				pointer = filepath.Join(current, pointer)
			}
			head, err := readBounded(filepath.Join(pointer, "HEAD"), 32768)
			if err != nil {
				return ""
			}
			return branchName(head)
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return ""
}
func branchName(data []byte) string {
	value := strings.TrimSpace(string(data))
	if strings.HasPrefix(value, "ref: refs/heads/") {
		return strings.TrimPrefix(value, "ref: refs/heads/")
	}
	if len(value) == 40 || len(value) == 64 {
		if _, err := hex.DecodeString(value); err == nil {
			return value[:8]
		}
	}
	return ""
}
func scanProcesses(proc string, uid uint32) ([]listener, []string) {
	result := []listener{}
	warnings := []string{}
	sockets := map[string][]socket{}
	for _, name := range []string{"tcp", "tcp6"} {
		data, err := readBounded(filepath.Join(proc, "net", name), 8*1024*1024)
		if err != nil {
			warnings = append(warnings, "Cannot read /proc/net/"+name)
			continue
		}
		for _, s := range parseTCP(data, uid) {
			sockets[s.inode] = append(sockets[s.inode], s)
		}
	}
	entries, err := boundedEntries(proc)
	if err != nil {
		return result, append(warnings, "Cannot enumerate /proc")
	}
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil || pid <= 0 {
			continue
		}
		base := filepath.Join(proc, entry.Name())
		info, err := os.Stat(base)
		if err != nil {
			continue
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != uid {
			continue
		}
		before, err := readBounded(filepath.Join(base, "stat"), 65536)
		if err != nil {
			continue
		}
		started := startTicks(before)
		if started == "" {
			continue
		}
		fds, err := boundedEntries(filepath.Join(base, "fd"))
		if err != nil {
			continue
		}
		owned := map[string]bool{}
		for _, fd := range fds {
			link, err := os.Readlink(filepath.Join(base, "fd", fd.Name()))
			if err == nil && strings.HasPrefix(link, "socket:[") && strings.HasSuffix(link, "]") {
				owned[strings.TrimSuffix(strings.TrimPrefix(link, "socket:["), "]")] = true
			}
		}
		name, _ := readBounded(filepath.Join(base, "comm"), 4096)
		exe, _ := os.Readlink(filepath.Join(base, "exe"))
		cwd, _ := os.Readlink(filepath.Join(base, "cwd"))
		status, _ := readBounded(filepath.Join(base, "status"), 65536)
		var memory uint64
		for _, line := range strings.Split(string(status), "\n") {
			if strings.HasPrefix(line, "VmRSS:") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					value, err := strconv.ParseUint(fields[1], 10, 64)
					if err == nil && value < 1<<50 {
						memory = value * 1024
					}
				}
			}
		}
		after, err := readBounded(filepath.Join(base, "stat"), 65536)
		if err != nil || startTicks(after) != started {
			continue
		}
		branch := ""
		matched := false
		for inode := range owned {
			for _, s := range sockets[inode] {
				if !matched {
					branch = branchFor(cwd)
					matched = true
				}
				result = append(result, listener{s.port, s.address, pid, strings.TrimSpace(string(name)), exe, cwd, branch, started, memory})
			}
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Port != result[j].Port {
			return result[i].Port < result[j].Port
		}
		if result[i].PID != result[j].PID {
			return result[i].PID < result[j].PID
		}
		return result[i].Address < result[j].Address
	})
	return result, warnings
}

// A process with an extreme FD count must not cause unbounded allocations.
func boundedEntries(path string) ([]os.DirEntry, error) {
	directory, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer directory.Close()
	entries, err := directory.ReadDir(65537)
	if err != nil && err != io.EOF {
		return nil, err
	}
	if len(entries) > 65536 {
		return nil, fmt.Errorf("directory exceeds inspection limit")
	}
	return entries, nil
}
