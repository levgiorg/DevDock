import Darwin
import Foundation
import Testing
@testable import DevDock

struct SecurityTests {
    private func fixture() -> Server {
        Server(port: 34567, pid: 12345, rootPid: 12300, processName: "node", addresses: ["127.0.0.1"],
               cwd: "/tmp/project", cwdExists: true, startedAt: Date(timeIntervalSince1970: 100),
               project: ProjectInfo(name: "fixture"), listenerExecutable: "/opt/homebrew/bin/node", processes: [],
               processStarts: [12345: Date(timeIntervalSince1970: 100)], pauseTargets: [:], memory: 0, cpu: 0,
               connections: 0, history: [], lastActive: Date(), isProtected: false, isPaused: false)
    }

    @Test func processActionsRejectReusedPidWrongUserSharedServicesAndInfrastructure() {
        let server = fixture()
        var snapshot = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: server.processStarts[server.pid]!)
        var sockets = SocketScan(listenerPidsByPort: [server.port: [server.pid]])
        func denial(_ executable: String = "/opt/homebrew/bin/node", cwd: String? = "/tmp/project") -> String? {
            ProcessControl.denialReason(server, sockets: sockets, snapshot: snapshot, executable: executable, cwd: cwd)
        }
        #expect(denial() == nil)
        snapshot = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: snapshot.startTime + 0.001)
        #expect(denial() != nil, "Even a sub-second PID reuse must fail")
        snapshot = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: server.processStarts[server.pid]!, uid: getuid() + 1)
        #expect(denial() != nil)
        snapshot = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: server.processStarts[server.pid]!)
        #expect(denial("/Applications/Docker.app/Contents/MacOS/com.docker.backend") != nil)
        #expect(denial(cwd: "/tmp/other") != nil)
        #expect(denial(cwd: nil) != nil)
        #expect(denial("/usr/bin/python3") != nil, "Exec without PID change must invalidate the row")
        sockets.listenerPidsByPort[server.port]?.insert(54321)
        #expect(denial() != nil)
        sockets.listenerPidsByPort = [server.port: [server.pid], 34568: [server.pid]]
        #expect(denial() != nil)
        sockets.listenerPidsByPort = [:]
        #expect(denial() != nil)
    }

    @Test func delayedSignalsRejectExecChdirAndPidReuse() throws {
        let server = fixture()
        let target = try #require(ProcessControl.SignalTarget(server))
        let snapshot = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: target.started)
        #expect(target.matches(snapshot, executable: target.executable, cwd: target.cwd))
        #expect(!target.matches(snapshot, executable: "/usr/bin/python3", cwd: target.cwd))
        #expect(!target.matches(snapshot, executable: target.executable, cwd: "/tmp/other"))
        #expect(!target.matches(nil, executable: target.executable, cwd: target.cwd))
        #expect(!target.matches(snapshot, executable: nil, cwd: target.cwd))
        let reused = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: target.started + 0.001)
        #expect(!target.matches(reused, executable: target.executable, cwd: target.cwd))
        let wrongUser = ProcSnapshot(pid: server.pid, ppid: 1, comm: "node", startTime: target.started, uid: getuid() + 1)
        #expect(!target.matches(wrongUser, executable: target.executable, cwd: target.cwd))
    }

    @Test func restartDoesNotInterpretProcessTitlesAsShellCode() {
        let executable = "/opt/homebrew/bin/node"
        #expect(ProcessControl.canLaunch(ProcArgs(executablePath: executable, arguments: [executable, "a b.js", "$(touch /tmp/not-run)", ""], environment: [:])))
        for args in [["next-server (v16)"], ["node; curl attacker"], []] {
            #expect(!ProcessControl.canLaunch(ProcArgs(executablePath: executable, arguments: args, environment: [:])))
        }
        #expect(!ProcessControl.canLaunch(ProcArgs(executablePath: "/bin/zsh", arguments: ["zsh", "-c", "anything"], environment: [:])))
    }

    @Test func containerActionsRequireExactIdentityStateAndMappings() throws {
        let id = String(repeating: "a", count: 64)
        var container = ContainerInfo(id: id, name: "audit", image: "busybox", runtime: .dockerDesktop(), publishedPorts: [34567])
        var inspect: [String: Any] = ["Id": id, "Name": "/audit", "State": ["Running": true, "Paused": false],
            "HostConfig": ["PortBindings": ["80/tcp": [["HostIp": "127.0.0.1", "HostPort": "34567"]]]]]
        var calls: [String] = []
        let transport: DockerEngine.Transport = { method, path, _, _ in
            calls.append(method + " " + path)
            return method == "GET" ? try? JSONSerialization.data(withJSONObject: inspect) : Data()
        }
        #expect(DockerEngine.perform(.stop, on: container, transport: transport))
        #expect(calls.last == "POST /containers/\(id)/stop?t=10")
        calls = []; inspect["Id"] = String(repeating: "b", count: 64)
        #expect(!DockerEngine.perform(.stop, on: container, transport: transport))
        #expect(calls.count == 1)
        inspect["Id"] = id; inspect["State"] = ["Running": false, "Paused": false]
        #expect(!DockerEngine.perform(.restart, on: container, transport: transport))
        container.isRunning = false
        #expect(DockerEngine.perform(.start, on: container, transport: transport))
        inspect["HostConfig"] = [:]
        #expect(!DockerEngine.perform(.start, on: container, transport: transport))
        container = ContainerInfo(id: "../other", name: "audit", image: "busybox", runtime: .dockerDesktop(), publishedPorts: [34567])
        calls = []
        #expect(!DockerEngine.perform(.stop, on: container, transport: transport))
        #expect(calls.isEmpty)
    }

    @Test func malformedDockerHTTPAndUntrustedTargetsFailClosed() {
        for response in [
            "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n[]",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n[]",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\n[]\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[]\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n[]",
        ] { #expect(DockerEngine.parseResponse(Data(response.utf8)) == nil) }
        #expect(!DockerEngine.allowedRequest("POST", "/containers/../stop"))
        #expect(!DockerEngine.allowedRequest("GET", "/info\r\nInjected: true"))
        #expect(!DockerEngine.allowedRequest("POST", "/containers/create"))
        #expect(!DockerEngine.isLocalSocket("tcp://example.com:2375"))
    }

    @Test func duplicatePortAttributionIsNeverGuessed() {
        let runtime = ContainerRuntime.dockerDesktop()
        let a = ContainerInfo(id: "a", name: "a", image: "x", runtime: runtime, publishedPorts: [34567])
        let b = ContainerInfo(id: "b", name: "b", image: "x", runtime: runtime, publishedPorts: [34567])
        #expect(ScanEngine.containersByPort([34567: runtime], states: [runtime: RuntimeSnapshot(containers: [a,b])]).isEmpty)
        var stopped = b; stopped.isRunning = false
        #expect(ScanEngine.uniqueContainer([a, stopped])?.id == a.id)
        #expect(ScanEngine.uniqueContainer([stopped])?.id == b.id)
    }

    @Test func sessionPathTraversalExternalSchemesAndTerminalEscapesAreRejected() {
        for id in ["../../secret", "x/../foo", "--help", "abc\n"] { #expect(!AgentSessionResolver.isValidSessionID(id)) }
        #expect(AgentSessionResolver.isValidSessionID("12345678-1234-1234-1234-123456789abc"))
        for value in ["file:///tmp/a", "javascript:alert(1)", "https://user:pass@example.com"] {
            #expect(!GitHubLookup.safeWebURL(URL(string: value)!))
        }
        #expect(GitHubLookup.safeWebURL(URL(string: "https://example.com/preview")!))
        #expect(GitHubLookup.queryValue("branch&per_page=500#x") == "branch%26per%5Fpage%3D500%23x")
        let hostile = "name\u{1b}]52;c;clipboard\u{7}\n\u{202e}evil"
        let clean = SafeText.terminal(hostile)
        #expect(!clean.contains("\u{1b}") && !clean.contains("\n") && !clean.contains("\u{202e}"))
        #expect(Span(hostile).text == clean)
    }

    @Test func commandsAreBoundedAndDoNotRunShellStartupFiles() {
        #expect(BoundedCommand.run("/usr/bin/printf", ["%s", "$(should-not-run)"]) == "$(should-not-run)")
        let start = Date()
        #expect(BoundedCommand.run("/bin/sleep", ["5"], timeout: 0.1) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(BoundedCommand.run("/usr/bin/printf", ["123456789"], limit: 3) == nil)
    }

    @Test func monitoredFilesCannotBlockOnFIFOsOrFollowSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("manifest")
        try Data("test".utf8).write(to: file)
        #expect(BoundedFile.text(file.path) == "test")
        #expect(BoundedFile.read(file.path, limit: 2, complete: true) == nil)
        #expect(BoundedFile.read(file.path, limit: 2, tail: true) == Data("st".utf8))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(BoundedFile.text(link.path) == nil)
        let fifo = root.appendingPathComponent("fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let start = Date()
        #expect(BoundedFile.text(fifo.path) == nil)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func projectExecutablesAreDiscoveredWithoutAddingTheirArbitraryNameToAnAllowlist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{\"name\":\"audit-server\"}".utf8).write(to: directory.appendingPathComponent("package.json"))
        let pid: pid_t = 12345
        let engine = ScanEngine(inspector: .init(usage: { _ in nil }, arguments: { _ in nil },
            currentDirectory: { _ in directory.path }, executablePath: { _ in "/tmp/audit-server" }))
        let sockets = SocketScan(listening: [ListeningSocket(port: 808, pid: pid, command: "audit-server", addresses: ["127.0.0.1"])])
        let processes = [pid: ProcSnapshot(pid: pid, ppid: 1, comm: "audit-server", startTime: Date())]
        var config = ScanConfig(minPort: 1, maxPort: 65535, allowlist: ["node"], linkClaude: false, linkCodex: false, showContainers: false)
        #expect(engine.scan(config, sockets: sockets, processes: processes, now: Date()).isEmpty)
        config.includeProjectExecutables = true
        #expect(engine.scan(config, sockets: sockets, processes: processes, now: Date()).first?.port == 808)
    }

    @Test func cliInstallNeverOverwritesCommandsOrUsesUnsafeDirectories() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("app")
        try Data("fixture".utf8).write(to: target)
        #expect(CommandLineTool.installLink(target: target.path, home: home.path) == nil)
        let link = home.appendingPathComponent(".local/bin/wtp")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(CommandLineTool.installLink(target: target.path, home: home.path) == nil)
        try FileManager.default.removeItem(at: link)
        try Data("existing command".utf8).write(to: link)
        #expect(CommandLineTool.installLink(target: target.path, home: home.path) != nil)
        #expect(try String(contentsOf: link, encoding: .utf8) == "existing command")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: home.appendingPathComponent(".local").path)
        #expect(CommandLineTool.installLink(target: target.path, home: home.path) != nil)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".local"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".local"), withDestinationURL: home)
        #expect(CommandLineTool.installLink(target: target.path, home: home.path) != nil)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("bin").path))
    }

    @MainActor @Test func devDockBrandUsesVectorPathsAndAdaptiveMenuBarImages() {
        let paths = DevDockMark.paths()
        #expect(paths.count == 2)
        for path in paths {
            #expect(path.bounds.minX >= 0 && path.bounds.maxX <= 164)
            #expect(path.bounds.minY >= 0 && path.bounds.maxY <= 128)
        }
        let mark = MenuBarIcon.image(glyph: .colon, count: nil)
        let count = MenuBarIcon.image(glyph: .colon, count: 3)
        #expect(mark.isTemplate)
        #expect(mark.size == NSSize(width: 20, height: 18))
        #expect(count.isTemplate && count.size.width > mark.size.width)
        #expect(!MenuBarIcon.image(glyph: .alert, count: 3).isTemplate)
        #expect(TerminalCommand.appIdentifier == "com.devdock.app")
        #expect(FeedbackLink.repository == "https://github.com/levgiorg/DevDock")
        #expect(FeedbackLink.site.absoluteString == FeedbackLink.repository)
        #expect(FeedbackLink.issue(.bug).path == "/levgiorg/DevDock/issues/new")
    }

    @Test func telemetryCannotBeEnabled() {
        Usage.setSharing(true)
        #expect(!Usage.isSharing)
        Usage.record(.active)
        #expect(UserDefaults.standard.stringArray(forKey: "usage.pending") == nil)
        #expect(!Preferences.CleanUpMode.allCases.contains(.automatic))
    }
}
