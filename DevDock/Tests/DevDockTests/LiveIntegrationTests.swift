import Darwin
import Foundation
import Testing
@testable import DevDock

/// Opt-in checks mutate only resources created by scripts/live-integration.py.
@Suite(.serialized)
struct LiveIntegrationTests {
    enum IntegrationFailure: Error { case stateDidNotConverge(String) }
    static let enabled = ProcessInfo.processInfo.environment["WTP_RUN_LIVE_TESTS"] == "1"

    @Test(.enabled(if: enabled)) func localListenerPauseResumeStopLeavesSiblingAlive() async throws {
        func launch() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-lk", "127.0.0.1", "0"]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        let target = try launch(), sibling = try launch()
        let targetIdentity = try #require(ProcessInspector.snapshot(target.processIdentifier))
        let siblingIdentity = try #require(ProcessInspector.snapshot(sibling.processIdentifier))
        defer {
            for identity in [targetIdentity, siblingIdentity] {
                if ProcessInspector.snapshot(identity.pid)?.startTime == identity.startTime { kill(identity.pid, SIGKILL) }
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        let engine = ScanEngine()
        let config = ScanConfig(minPort: 1, maxPort: 65535, allowlist: ["nc"], linkClaude: false, linkCodex: false, showContainers: false)
        let rows = engine.scan(config)
        let server = try #require(rows.first { $0.pid == targetIdentity.pid })
        #expect(rows.contains { $0.pid == siblingIdentity.pid })
        #expect(ProcessControl.pause(server))
        try await Task.sleep(for: .milliseconds(100))
        #expect(ProcessInspector.snapshot(targetIdentity.pid)?.isStopped == true)
        #expect(ProcessInspector.snapshot(siblingIdentity.pid)?.isStopped == false)
        #expect(ProcessControl.resume(server))
        try await Task.sleep(for: .milliseconds(100))
        #expect(ProcessInspector.snapshot(targetIdentity.pid)?.isStopped == false)
        #expect(ProcessControl.stop(server))
        for _ in 0..<30 where target.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!target.isRunning)
        #expect(sibling.isRunning)
        #expect(!ProcessControl.stop(server), "The stale row must not authorize another signal")
    }

    @Test(.enabled(if: enabled)) func restartExecutesIntactArgvWithoutAShell() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-lk", "127.0.0.1", "0"]
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let original = try #require(ProcessInspector.snapshot(process.processIdentifier))
        let canonicalDirectory = try #require(ProcessInspector.currentDirectory(original.pid))
        try #require(URL(fileURLWithPath: canonicalDirectory).lastPathComponent == directory.lastPathComponent)
        var replacement: ProcSnapshot?
        defer {
            // If an assertion fails before the replacement is assigned, recover
            // only this test's listener in its private, unique working directory.
            if replacement == nil {
                replacement = ProcessInspector.allProcesses().values.first {
                    $0.pid != original.pid && $0.uid == getuid() && $0.startTime >= original.startTime
                        && ProcessInspector.currentDirectory($0.pid) == canonicalDirectory
                        && ProcessInspector.executablePath($0.pid) == "/usr/bin/nc"
                }
            }
            for identity in [original, replacement].compactMap({ $0 }) {
                if ProcessInspector.snapshot(identity.pid)?.startTime == identity.startTime { kill(identity.pid, SIGKILL) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(200))
        let engine = ScanEngine()
        let config = ScanConfig(minPort: 1, maxPort: 65535, allowlist: ["nc"], linkClaude: false, linkCodex: false, showContainers: false)
        let row = try #require(engine.scan(config).first { $0.pid == original.pid })
        #expect(row.launch.map(ProcessControl.canLaunch) == true)
        let ok = await withCheckedContinuation { continuation in
            ProcessControl.restart(row) { continuation.resume(returning: $0) }
        }
        #expect(ok)
        try await Task.sleep(for: .milliseconds(300))
        let next = try #require(engine.scan(config).first { $0.cwd == canonicalDirectory && $0.pid != original.pid })
        replacement = ProcessInspector.snapshot(next.pid)
        #expect(next.listenerExecutable == "/usr/bin/nc")
        #expect(next.launch?.arguments.dropFirst() == ["-lk", "127.0.0.1", "0"])
    }

    @Test(.enabled(if: enabled)) func gitWorktreeAndClaudeSessionAreReadOnlyAndAccuratelyResolved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo"), worktree = root.appendingPathComponent("worktree")
        #expect(BoundedCommand.run("/usr/bin/git", ["init", "-b", "main", repo.path]) != nil)
        try Data("{\"name\":\"audit-project\",\"dependencies\":{\"vite\":\"7\"}}".utf8).write(to: repo.appendingPathComponent("package.json"))
        #expect(BoundedCommand.run("/usr/bin/git", ["-C", repo.path, "add", "package.json"]) != nil)
        #expect(BoundedCommand.run("/usr/bin/git", ["-C", repo.path, "-c", "user.name=Audit", "-c", "user.email=audit@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"]) != nil)
        #expect(BoundedCommand.run("/usr/bin/git", ["-C", repo.path, "worktree", "add", "-b", "audit/fixture", worktree.path]) != nil)
        let before = try Data(contentsOf: worktree.appendingPathComponent("package.json"))
        let resolver = ProjectResolver()
        let project = resolver.resolve(cwd: worktree.path, command: "vite")
        #expect(project.isWorktree && project.branch == "audit/fixture" && project.name == "audit-project")
        let sessionID = UUID().uuidString.lowercased()
        let sessions = root.appendingPathComponent(".claude/projects/fixture")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let transcript = sessions.appendingPathComponent(sessionID + ".jsonl")
        let json = try JSONSerialization.data(withJSONObject: ["type": "custom-title", "customTitle": "Audit session", "cwd": worktree.path])
        try (json + Data("\n".utf8)).write(to: transcript)
        let agent = AgentSessionResolver(home: root).resolve(environment: ["CLAUDE_CODE_SESSION_ID": sessionID], cwd: worktree.path, codex: false)
        #expect(agent?.id == sessionID && agent?.title == "Audit session" && agent?.directory == worktree.path)
        #expect(try Data(contentsOf: worktree.appendingPathComponent("package.json")) == before)
        #expect(try Data(contentsOf: transcript) == json + Data("\n".utf8))
    }

    @Test(.enabled(if: enabled)) func dockerLifecycleTargetsOnlyAuditContainer() throws {
        let env = ProcessInfo.processInfo.environment
        let id = try #require(env["WTP_AUDIT_DOCKER_ID"])
        let sentinelID = try #require(env["WTP_AUDIT_DOCKER_SENTINEL_ID"])
        let nonce = try #require(env["WTP_AUDIT_NONCE"])
        let runtime = ContainerRuntime.dockerDesktop()
        func inspect(_ id: String) throws -> [String: Any] {
            let data = try #require(DockerEngine.request("GET", "/containers/\(id)/json", runtime: runtime))
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        for fixtureID in [id, sentinelID] {
            let json = try inspect(fixtureID)
            let labels = (json["Config"] as? [String: Any])?["Labels"] as? [String: String]
            try #require(labels?["com.devdock.audit"] == nonce, "Only the harness-created fixtures may be mutated")
        }
        func current(_ phase: String, running: Bool = true, paused: Bool = false) throws -> ContainerInfo {
            print("Docker fixture phase: \(phase)")
            // Docker Desktop may briefly return the pre-action list snapshot.
            // Verify eventual convergence instead of mistaking an accepted POST
            // or a single stale response for a completed lifecycle transition.
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if let rows = DockerEngine.containers(runtime), let row = rows.first(where: { $0.id == id }),
                   row.isRunning == running, row.isPaused == paused { return row }
                usleep(100_000)
            }
            throw IntegrationFailure.stateDidNotConverge(phase)
        }
        var container = try current("initial")
        #expect(container.bindings.contains { $0.hostIP == "127.0.0.1" && $0.containerPort == 8080 })
        #expect(DockerEngine.perform(.pause, on: container))
        container = try current("paused", paused: true); #expect(container.isPaused)
        #expect(DockerEngine.perform(.unpause, on: container))
        container = try current("unpaused"); #expect(!container.isPaused)
        #expect(DockerEngine.perform(.restart, on: container))
        container = try current("restarted"); #expect(container.isRunning)
        #expect(DockerEngine.perform(.stop, on: container))
        container = try current("stopped", running: false); #expect(!container.isRunning)
        #expect(!DockerEngine.perform(.stop, on: container), "A stale lifecycle action is refused")
        #expect(DockerEngine.perform(.start, on: container))
        container = try current("started"); #expect(container.isRunning)
        let sentinel = try inspect(sentinelID)
        #expect((sentinel["State"] as? [String: Any])?["Running"] as? Bool == true)
        // Runtime discovery works even without relying on lsof attribution.
        #expect(ContainerRuntime.available().contains(runtime))
    }
}
