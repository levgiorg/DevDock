# DevDock Linux terminal companion

This first Linux build is a command-line companion, not a desktop/tray app. It has no runtime dependencies, telemetry, privileged helper or remote Docker context support. Run it as your ordinary user.

```sh
./devdock list
./devdock list --json
./devdock list --docker=false
./devdock --version
./devdock docker stop FULL_64_CHARACTER_CONTAINER_ID
```

Native inspection is **read-only**. It lists current-user TCP listeners from Linux procfs, PIDs, executable paths, working directories, resident memory and Git branches/worktrees. Shared socket owners appear separately; no process is killed or inferred process tree controlled. PID start ticks are checked across inspection. Restrictive procfs permissions, PID/network namespaces and exited processes can limit visibility. CPU histories, agent-session attribution and the macOS UI/alerts are not implemented on Linux yet.

Docker discovery uses only rootless `/run/user/<uid>/docker.sock`, Docker Desktop's `~/.docker/run/docker.sock`, or `/var/run/docker.sock`. It ignores `DOCKER_HOST`, remote contexts and network proxies. It shows full container IDs, state, image and TCP mappings, including configured stopped-container mappings. Operations are start, stop, restart, pause and unpause. A command asks you to type the full ID; `--yes` is an explicit automation opt-in. Identity, state and bindings are inspected again before the request. Read-only Docker access still gives the process access to a powerful daemon; do not grant Docker-group access solely for this utility.

Docker requests have socket-owner/type checks, endpoint/ID allowlists, deadlines, header/body bounds and no redirects. Very large or slow engines may return a warning instead of a complete listing. Inspect original Docker tools when a result is ambiguous. No root or sudo action is performed.

Build/test with the Go version pinned by `go.mod`:

```sh
cd linux
go test -race ./...
go vet ./...
cd ..
./scripts/build-linux.sh 2.8.0-beta.1 amd64
./scripts/build-linux.sh 2.8.0-beta.1 arm64
```

Release tarballs include the executable, this guide, LICENSE and third-party notices. Extract the archive, verify SHA256SUMS, then run `./devdock --help`; optionally copy it into your user's `~/.local/bin`. No installer script or automatic service is required.
