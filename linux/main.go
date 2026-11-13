// DevDock for Linux is a terminal companion. Native process inspection is
// read-only; Docker mutations require a full ID and explicit confirmation.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
	"text/tabwriter"
	"time"
	"unicode"
)

var version = "development"

type report struct {
	Processes  []listener  `json:"processes"`
	Containers []container `json:"containers"`
	Warnings   []string    `json:"warnings"`
}

func clean(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || (r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) {
			return -1
		}
		return r
	}, s)
}

func run(args []string, in io.Reader, out, errout io.Writer) error {
	if len(args) > 0 && (args[0] == "version" || args[0] == "--version") {
		fmt.Fprintf(out, "DevDock %s (%s/%s)\n", version, runtime.GOOS, runtime.GOARCH)
		return nil
	}
	if len(args) > 0 && args[0] == "docker" {
		return dockerCommand(args[1:], in, out, errout)
	}
	flags := flag.NewFlagSet("devdock list", flag.ContinueOnError)
	flags.SetOutput(errout)
	asJSON := flags.Bool("json", false, "Print machine-readable JSON")
	withDocker := flags.Bool("docker", true, "Inspect a known local Docker Unix socket")
	if len(args) > 0 && args[0] == "list" {
		args = args[1:]
	}
	flags.Usage = func() {
		fmt.Fprintln(errout, "DevDock Linux terminal companion\nUsage: devdock [list] [--json] [--docker=false]\n       devdock docker <start|stop|restart|pause|unpause> <full-container-id> [--yes]\n       devdock --version\n\nNative process inspection is read-only. No root permission, telemetry or remote Docker contexts.")
		flags.PrintDefaults()
	}
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected argument; use --help")
	}
	if runtime.GOOS != "linux" {
		return errors.New("Linux /proc is required; use the native DevDock app on macOS")
	}
	processes, warnings := scanProcesses("/proc", uint32(os.Getuid()))
	result := report{Processes: processes, Containers: []container{}, Warnings: warnings}
	if *withDocker {
		socket := discoverSocket()
		if socket != "" {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			client := newDocker(socket)
			defer client.close()
			containers, err := client.list(ctx)
			if err != nil {
				result.Warnings = append(result.Warnings, "Docker: "+clean(err.Error()))
			} else {
				result.Containers = containers
			}
		}
	}
	if *asJSON {
		encoder := json.NewEncoder(out)
		encoder.SetIndent("", "  ")
		return encoder.Encode(result)
	}
	w := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "PORT\tPID\tPROCESS\tMEMORY\tPROJECT / BRANCH")
	for _, p := range result.Processes {
		project := p.Directory
		if p.Branch != "" {
			project += " · " + p.Branch
		}
		fmt.Fprintf(w, "%d\t%d\t%s\t%d MiB\t%s\n", p.Port, p.PID, clean(p.Name), p.MemoryBytes/(1024*1024), clean(project))
	}
	if err := w.Flush(); err != nil {
		return err
	}
	if len(result.Processes) == 0 {
		fmt.Fprintln(out, "No readable current-user TCP listeners.")
	}
	for _, c := range result.Containers {
		fmt.Fprintf(out, "Docker %s  %s  %s  %s\n", clean(c.Name), c.ID, clean(c.State), clean(strings.Join(c.Ports, ", ")))
	}
	for _, warning := range result.Warnings {
		fmt.Fprintln(errout, "Warning:", clean(warning))
	}
	return nil
}

func dockerCommand(args []string, in io.Reader, out, errout io.Writer) error {
	if len(args) < 2 {
		return errors.New("usage: devdock docker <start|stop|restart|pause|unpause> <full-container-id> [--yes]")
	}
	action, id := args[0], args[1]
	if !validAction(action) || !validID(id) {
		return errors.New("use a supported action and an exact 64-character lowercase container ID")
	}
	yes := false
	for _, arg := range args[2:] {
		if arg != "--yes" {
			return errors.New("unexpected argument")
		}
		yes = true
	}
	socket := discoverSocket()
	if socket == "" {
		return errors.New("no trusted local Docker Unix socket found")
	}
	client := newDocker(socket)
	defer client.close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	expected, err := client.inspect(ctx, id)
	cancel()
	if err != nil {
		return err
	}
	if !allowedState(action, expected) {
		return errors.New("container state does not allow this action")
	}
	fmt.Fprintf(out, "%s container %s (%s), ports %s\n", action, clean(expected.Name), id, clean(strings.Join(expected.portStrings(), ", ")))
	if !yes {
		fmt.Fprintln(out, "Type the complete container ID to confirm:")
		line, err := bufio.NewReader(io.LimitReader(in, 256)).ReadString('\n')
		if err != nil {
			return errors.New("confirmation requires the full ID followed by Enter")
		}
		if strings.TrimSpace(line) != id {
			return errors.New("cancelled; container identity was not confirmed")
		}
	}
	ctx, cancel = context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := client.perform(ctx, action, expected); err != nil {
		return err
	}
	fmt.Fprintln(out, "Docker action accepted. Run devdock list to refresh state.")
	return nil
}

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "devdock:", clean(err.Error()))
		os.Exit(1)
	}
}
