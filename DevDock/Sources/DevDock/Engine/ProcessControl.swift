import Darwin
import Foundation

/// Signals only the freshly verified listener. Process trees are for attribution and
/// resource accounting, never authority to kill a supervisor or unrelated descendants.
enum ProcessControl {
    struct SignalTarget {
        let pid: pid_t
        let started: Date
        let executable: String
        let cwd: String

        init?(_ server: Server) {
            guard let started = server.processStarts[server.pid],
                  let executable = server.listenerExecutable, let cwd = server.cwd else { return nil }
            self.pid = server.pid
            self.started = started
            self.executable = executable
            self.cwd = cwd
        }

        func matches(_ snapshot: ProcSnapshot?, executable: String?, cwd: String?) -> Bool {
            guard pid > 1, pid != getpid(), let snapshot else { return false }
            return snapshot.pid == pid && snapshot.uid == getuid() && snapshot.startTime == started
                && executable == self.executable && cwd == self.cwd
                && !ProcessControl.isInfrastructure(executable: self.executable, name: snapshot.comm)
        }

        var hasExited: Bool {
            if let current = ProcessInspector.snapshot(pid) { return current.startTime != started }
            return kill(pid, 0) == -1 && errno == ESRCH
        }
    }

    static var forceQuitDelay: TimeInterval {
        let seconds = UserDefaults.standard.double(forKey: Preferences.forceQuitSeconds)
        return seconds.isFinite && seconds > 0 ? min(seconds, 60) : 3
    }

    /// A second kernel/socket snapshot is required immediately before an action.
    /// Ambiguous shared ports, multiple services in one PID, protected services,
    /// agent sessions and container infrastructure fail closed.
    static func denialReason(_ server: Server, sockets: SocketScan,
                             snapshot: ProcSnapshot?, executable: String?, cwd: String?) -> String? {
        guard server.container == nil, server.pid > 1, server.pid != getpid(),
              let expected = server.processStarts[server.pid], let snapshot,
              snapshot.pid == server.pid, snapshot.uid == getuid(), snapshot.startTime == expected else {
            return "The process identity changed or is unavailable. Refresh and try again."
        }
        guard !server.isProtected, server.controlWarning == nil, let executable,
              let expectedExecutable = server.listenerExecutable, executable == expectedExecutable,
              !isInfrastructure(executable: executable, name: snapshot.comm),
              let cwd, let expectedDirectory = server.cwd, cwd == expectedDirectory else {
            return "This service is protected, shared infrastructure, or its working directory changed."
        }
        var owners = sockets.listenerPidsByPort[server.port] ?? []
        for socket in sockets.listening where socket.port == server.port { owners.insert(socket.pid) }
        guard owners == [server.pid] else { return "Port ownership is ambiguous or the service stopped. Refresh and try again." }
        let otherPorts = sockets.listenerPidsByPort.filter { $0.key != server.port && $0.value.contains(server.pid) }
        guard otherPorts.isEmpty,
              !sockets.listening.contains(where: { $0.pid == server.pid && $0.port != server.port }) else {
            return "This process serves multiple ports. Manage it in its original terminal to avoid stopping shared services."
        }
        return nil
    }

    static func isInfrastructure(executable: String, name: String) -> Bool {
        let forbidden: Set<String> = ["launchd", "kernel_task", "docker", "docker-proxy", "com.docker.backend",
            "OrbStack", "OrbStack Helper", "limactl", "ssh", "sshd", "claude", "codex", "Conductor",
            "sh", "bash", "zsh", "fish", "dash", "turbo", "nx"]
        let lower = executable.lowercased()
        return forbidden.contains(name) || forbidden.contains((executable as NSString).lastPathComponent)
            || lower.contains(".app/contents/") && !lower.contains("/python.framework/")
            || lower.contains("@anthropic-ai/claude-code") || lower.contains("/codex/")
    }

    static func validate(_ server: Server) -> String? {
        denialReason(server, sockets: SocketScanner.scan(), snapshot: ProcessInspector.snapshot(server.pid),
                     executable: ProcessInspector.executablePath(server.pid), cwd: ProcessInspector.currentDirectory(server.pid))
    }

    @discardableResult
    static func stop(_ server: Server, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard validate(server) == nil, let target = SignalTarget(server),
              signal(SIGTERM, target: target) else { completion?(false); return false }
        // A paused process cannot handle SIGTERM until continued.
        _ = signal(SIGCONT, target: target)
        DispatchQueue.global().asyncAfter(deadline: .now() + forceQuitDelay) {
            // Exec/chdir can change identity without changing the PID's birth time.
            // Recheck socket ownership and shared-service exclusions as well as
            // executable/directory after the grace period. Uncertainty fails closed.
            if validate(server) == nil { _ = signal(SIGKILL, target: target) }
            let deadline = Date().addingTimeInterval(0.5)
            while !target.hasExited && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
            let stopped = target.hasExited
            if let completion { DispatchQueue.main.async { completion(stopped) } }
        }
        return true
    }

    @discardableResult
    static func pause(_ server: Server) -> Bool { act(SIGSTOP, server: server) }
    @discardableResult
    static func resume(_ server: Server) -> Bool { act(SIGCONT, server: server) }

    private static func act(_ value: Int32, server: Server) -> Bool {
        guard validate(server) == nil, let target = SignalTarget(server) else { return false }
        return signal(value, target: target)
    }

    private static func signal(_ value: Int32, target: SignalTarget) -> Bool {
        let executable = ProcessInspector.executablePath(target.pid)
        let cwd = ProcessInspector.currentDirectory(target.pid)
        guard target.matches(ProcessInspector.snapshot(target.pid), executable: executable, cwd: cwd) else { return false }
        return kill(target.pid, value) == 0
    }

    /// Only intact executable argv can be restarted. Never turn a mutable process
    /// title into shell source or replay a shell's startup scripts.
    static func canLaunch(_ launch: ProcArgs) -> Bool {
        guard launch.executablePath.hasPrefix("/"), !launch.executablePath.utf8.contains(0),
              let first = launch.arguments.first, !first.isEmpty,
              !launch.arguments.contains(where: { $0.utf8.contains(0) }) else { return false }
        let executable = (launch.executablePath as NSString).lastPathComponent
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]
        let sameAbsolute = first.hasPrefix("/") && URL(fileURLWithPath: first).resolvingSymlinksInPath()
            == URL(fileURLWithPath: launch.executablePath).resolvingSymlinksInPath()
        return !shells.contains(executable) && (first == launch.executablePath || first == executable || sameAbsolute)
    }

    static func restart(_ server: Server, completion: ((Bool) -> Void)? = nil) {
        guard let launch = server.launch, canLaunch(launch), let cwd = server.cwd,
              server.launchDirectory == cwd, server.cwdExists, validate(server) == nil else { completion?(false); return }
        stop(server) { stopped in
            guard stopped else { completion?(false); return }
            DispatchQueue.global().async {
                // Refuse to create a duplicate if a supervisor already restarted it.
                let free = !SocketScanner.scan().listening.contains { $0.port == server.port }
                let result = free && spawn(launch, cwd: cwd)
                DispatchQueue.main.async { completion?(result) }
            }
        }
    }

    private static func spawn(_ launch: ProcArgs, cwd: String) -> Bool {
        guard canLaunch(launch), FileManager.default.isExecutableFile(atPath: launch.executablePath) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = Array(launch.arguments.dropFirst())
        process.environment = launch.environment
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        // Never create a predictable log file that can be replaced by a symlink,
        // or persist output that may contain tokens from a monitored process.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run(); return true } catch { return false }
    }
}
