import AppKit
import Combine
import Foundation

@MainActor
final class ServerMonitor: ObservableObject {
    @Published private(set) var servers: [Server] = [] {
        didSet {
            for port in servers.map(\.port).sorted() where portColorIndices[port] == nil {
                portColorIndices[port] = portColorIndices.count
            }
        }
    }
    /// Keep port identities stable across reordering, filtering, and restarts.
    private var portColorIndices: [Int: Int] = [:]
    @Published var actionError: String?
    @Published private(set) var hasScanned = false
    @Published private(set) var systemMemory: SystemMemory?
    /// Whole-Mac CPU, as a share of all cores.
    @Published private(set) var systemCPU: Double?
    /// Memory by app for everything that isn't a dev server, largest first.
    @Published private(set) var otherApps: [AppMemory] = []
    @Published var allowlist: Set<String> = ServerMonitor.defaultAllowlist
    /// Set from outside the popover (e.g. a notification's Details button).
    @Published var pendingRoute: PopoverRoute?

    /// Off in the `wtp` terminal UI, so it never duplicates the menu bar app's
    /// notifications or automatic clean up.
    var handlesAlerts = true

    /// Someone is looking at the servers: the popover is open, or `wtp` runs.
    /// Container stats then follow the scan interval; otherwise every 5 seconds,
    /// since each sample makes the engine read its VM's cgroups.
    var isWatched = false {
        didSet { updateContainerSampling() }
    }

    private func updateContainerSampling() {
        let scanInterval = max(defaults.double(forKey: Preferences.scanInterval), 1)
        engine.containerMonitor.setSampleInterval(isWatched ? scanInterval : max(scanInterval, 5))
    }

    var minPort: Int = 1
    var maxPort: Int = 65535

    static let defaultAllowlist: Set<String> = [
        "node", "npm", "npx", "deno", "bun",
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",
        "ruby", "rails", "puma", "unicorn",
        "php", "php-fpm",
        "java", "gradle", "mvn",
        "go", "air",
        "cargo", "rustc",
        "dotnet",
        "beam.smp", "elixir", "mix",
        "nginx", "httpd", "apache",
        "postgres", "mysql", "redis-server", "mongod",
        "docker-proxy",
    ]

    let github = GitHubLookup()
    private let engine = ScanEngine()
    private let appUsage = AppUsageScanner()
    private let cpuSampler = SystemCPUSampler()
    private let queue = DispatchQueue(label: "com.devdock.scan", qos: .utility)
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isScanning = false
    private var defaultsObserver: AnyCancellable?
    /// Servers we've already acted on in Clean up (notified or auto-stopped).
    private var handledCleanUps = Set<String>()

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: "allowlist") as? [String] { allowlist = Set(saved) }
        let min = defaults.integer(forKey: "minPort")
        let max = defaults.integer(forKey: "maxPort")
        if (1...65535).contains(min) { minPort = min }
        if (minPort...65535).contains(max) { maxPort = max }
    }

    // MARK: - Preferences

    private var defaults: UserDefaults { .standard }

    /// Memory above which a server needs attention.
    var alertThreshold: UInt64 {
        let gigabytes = defaults.double(forKey: Preferences.thresholdGB)
        return UInt64((gigabytes.isFinite && gigabytes > 0 ? min(gigabytes, 1024) : 2) * Format.gigabyte)
    }

    var idleThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpIdleHours), 1)) * 3600 }
    var longRunningThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpRunningDays), 1)) * 86400 }
    var cleanUpMode: Preferences.CleanUpMode { defaults.string(forKey: Preferences.cleanUpMode) == "off" ? .off : .ask }

    private var scanConfig: ScanConfig {
        ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist,
                   protected: Set(defaults.stringArray(forKey: Preferences.protectedProcesses) ?? Preferences.defaultProtected),
                   linkClaude: defaults.bool(forKey: Preferences.linkClaude),
                   linkCodex: defaults.bool(forKey: Preferences.linkCodex),
                   linkConductor: defaults.bool(forKey: Preferences.linkConductor),
                   linkPane: defaults.bool(forKey: Preferences.linkPane),
                   showBranches: defaults.bool(forKey: Preferences.showBranches),
                   showBranchPrefixes: defaults.bool(forKey: Preferences.showBranchPrefixes),
                   showContainers: defaults.bool(forKey: Preferences.showContainers),
                   includeProjectExecutables: allowlist == Self.defaultAllowlist)
    }

    // MARK: - Scanning

    func start() {
        guard timer == nil else { return }
        scan()
        scheduleTimer()
        // Settings changes (scan interval, thresholds, integrations) apply on the next scan.
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleTimer()
                    self?.updateContainerSampling()
                    self?.objectWillChange.send()
                }
            }
    }

    private func scheduleTimer() {
        let interval = max(defaults.double(forKey: Preferences.scanInterval), 1)
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let config = scanConfig
        queue.async { [engine, appUsage, cpuSampler] in
            let result = engine.scan(config)
            let system = ProcessInspector.systemMemory()
            let cpu = cpuSampler.sample()
            let apps = AppUsageScanner.excludingContainers(appUsage.scan(excluding: Set(result.flatMap { $0.processStarts.keys })), servers: result)
            Task { @MainActor in
                self.servers = result
                self.systemMemory = system
                if let cpu { self.systemCPU = cpu }
                self.otherApps = apps
                self.hasScanned = true
                self.isScanning = false
                if self.handlesAlerts {
                    AlertCenter.shared.evaluate(result, threshold: self.alertThreshold)
                    self.handleCleanUp()
                }
                // Keep previews and PRs roughly fresh in the background (no-op when disabled).
                result.forEach { self.github.refresh($0, maxAge: 300) }
            }
        }
    }

    /// Runs a scan synchronously. Used by snapshot mode.
    /// For `wtp list`, which exits after one look. Containers are measured off
    /// the scan queue, so a scan has to give their list and two stats samples
    /// time to arrive. Waits only when a runtime is being watched. Returns the
    /// runtimes that never answered.
    func scanForOneLook(timeout: TimeInterval = 3) -> [String] {
        engine.containerMonitor.setSampleInterval(1)
        scanNow()
        let watched = queue.sync { engine.containerMonitor.watchedRuntimes }
        guard !watched.isEmpty else {
            // CPU is measured between two scans.
            usleep(500_000)
            scanNow()
            return []
        }
        let deadline = Date().addingTimeInterval(timeout)
        var states = engine.containerMonitor.snapshot(watched)
        while Date() < deadline, !states.values.allSatisfy(\.isSettled) {
            usleep(100_000)
            states = engine.containerMonitor.snapshot(watched)
        }
        scanNow()
        return states.filter { $0.value.listedAt == nil || $0.value.listFailing }.keys.map(\.name).sorted()
    }

    func scanNow() {
        let config = scanConfig
        servers = queue.sync { engine.scan(config) }
        systemMemory = ProcessInspector.systemMemory()
        if let cpu = queue.sync(execute: { cpuSampler.sample() }) { systemCPU = cpu }
        let excluded = Set(servers.flatMap { $0.processStarts.keys })
        otherApps = AppUsageScanner.excludingContainers(queue.sync { appUsage.scan(excluding: excluded) }, servers: servers)
        hasScanned = true
    }

    // MARK: - Derived

    var totalMemory: UInt64 { ServerResources(servers).memory }
    var totalCPU: Double { ServerResources(servers).cpu }
    /// Servers' CPU as a share of the whole Mac, comparable with `systemCPU`.
    var serversShareOfCPU: Double { totalCPU / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) }
    var needsAttention: Bool { servers.contains { $0.status(alertThreshold: alertThreshold) == .attention } }

    func server(port: Int) -> Server? { servers.first { $0.port == port } }

    func colorIndex(for port: Int) -> Int { portColorIndices[port] ?? 0 }

    func status(of server: Server) -> ServerStatus { server.status(alertThreshold: alertThreshold) }

    /// A paused server was kept on purpose, so it's never suggested or auto-stopped.
    func cleanUpReason(for server: Server) -> CleanUpReason? {
        Self.cleanUpReason(for: server, mode: cleanUpMode, idleThreshold: idleThreshold, longRunningThreshold: longRunningThreshold,
                           deletedWorktree: defaults.bool(forKey: Preferences.cleanUpDeletedWorktree))
    }

    nonisolated static func cleanUpReason(for server: Server, mode: Preferences.CleanUpMode, idleThreshold: TimeInterval,
                              longRunningThreshold: TimeInterval, deletedWorktree: Bool) -> CleanUpReason? {
        guard !server.isProtected, !server.isPaused, mode != .off else { return nil }
        // A container's traffic can stay inside its compose network, where the
        // Mac never sees it, so idle and uptime don't say it's unused. Only a
        // leak is listed, and leaks are never preselected or stopped automatically.
        if server.container != nil {
            return server.isLeaking() ? .leaking(UInt64(max(server.memoryGrowth, 0))) : nil
        }
        if !server.cwdExists {
            return deletedWorktree ? .worktreeDeleted : nil
        }
        if server.idleFor >= idleThreshold { return .idle(server.idleFor) }
        if let uptime = server.uptime, uptime >= longRunningThreshold { return .longRunning(uptime) }
        if server.isLeaking() { return .leaking(UInt64(max(server.memoryGrowth, 0))) }
        return nil
    }

    /// Servers worth suggesting in Clean up. Leaking ones are listed but not
    /// preselected, since they're usually still in use.
    var cleanUpCandidates: [(server: Server, reason: CleanUpReason)] {
        servers.compactMap { server in cleanUpReason(for: server).map { (server, $0) } }
    }

    var suggestedCleanUpCount: Int {
        cleanUpCandidates.filter { !$0.reason.isLeak }.count
    }

    // MARK: - Automatic clean up

    /// In Ask mode, tells you once when servers start qualifying. In Automatic
    /// mode, stops them. Leaking servers are never stopped automatically.
    private func handleCleanUp() {
        let candidates = cleanUpCandidates.filter { !$0.reason.isLeak }
        let keys = Set(candidates.map { key(for: $0.server) })
        let fresh = candidates.filter { !handledCleanUps.contains(key(for: $0.server)) }
        handledCleanUps.formIntersection(keys)
        guard !fresh.isEmpty else { return }
        fresh.forEach { handledCleanUps.insert(key(for: $0.server)) }

        let notify = defaults.bool(forKey: Preferences.cleanUpNotify)
        switch cleanUpMode {
        case .off:
            return
        case .ask:
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: false) }
        case .automatic:
            Usage.record(.autoCleanUp)
            // Legacy Automatic settings are treated as Ask; idle time is not authority to kill.
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: false) }
        }
    }

    private func key(for server: Server) -> String { server.identityKey }

    // MARK: - Actions

    /// Containers stop through their runtime, never by signalling its helper.
    private func confirm(_ action: String, server: Server) -> Bool {
        // The TUI has its own confirmation and captures the selected identity.
        if TerminalCommand.isRequested || Bundle.main.bundleURL.pathExtension != "app" { return true }
        let alert = NSAlert()
        alert.messageText = "\(action) \(server.listTitle) on :\(server.port)?"
        if let container = server.container {
            alert.informativeText = "Container: \(container.name)\nID: \(container.id)\nRuntime: \(container.runtime.name)\nThis affects every port and service in this container."
        } else {
            alert.informativeText = "PID: \(server.pid)\nFolder: \(server.cwd ?? "Unknown")\nOnly the verified listener will receive a signal."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: action)
        return alert.runModal() == .alertSecondButtonReturn
    }

    func start(_ server: Server) {
        guard let container = server.container, !container.isRunning, confirm("Start", server: server) else { return }
        DockerEngine.start(container, completion: containerCompletion(container))
    }

    private func containerCompletion(_ container: ContainerInfo) -> (Bool) -> Void {
        { [weak self] ok in
            if !ok { self?.actionError = "The container action failed or its identity, state or port mappings changed. Refresh and try again." }
            self?.engine.containerMonitor.requestList(for: container.runtime)
            self?.engine.containerMonitor.forgetStart(of: container)
            self?.scan()
        }
    }

    @discardableResult
    func stop(_ server: Server) -> Bool {
        guard confirm("Stop", server: server) else { return false }
        if let container = server.container {
            DockerEngine.stop(container, completion: containerCompletion(container))
        } else {
            if let reason = ProcessControl.validate(server) { actionError = reason; return false }
            ProcessControl.stop(server) { [weak self] ok in
                if !ok { self?.actionError = "The process could not be stopped safely." }
                self?.scan()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scan() }
        return true
    }

    /// Stops each container or process once, however many ports it publishes.
    func stop(_ servers: [Server]) {
        var seen = Set<String>()
        for server in servers where seen.insert(server.container?.id ?? String(server.rootPid)).inserted {
            stop(server)
        }
    }

    func restart(_ server: Server) {
        guard confirm("Restart", server: server) else { return }
        if let container = server.container {
            DockerEngine.restart(container, completion: containerCompletion(container))
        } else {
            ProcessControl.restart(server) { [weak self] ok in
                if !ok { self?.actionError = "Restart was refused: the process changed, has no intact executable arguments, or the port is still occupied. Use its original terminal." }
                self?.scan()
            }
        }
    }

    /// Restart reruns the launch command, or for containers asks the runtime.
    func canRestart(_ server: Server) -> Bool {
        server.container?.isRunning == true || (server.container == nil && server.launch.map(ProcessControl.canLaunch) == true && server.cwdExists && !server.isProtected)
    }

    func pause(_ servers: [Server]) {
        for server in servers where !server.isPaused { togglePause(server) }
    }

    func togglePause(_ server: Server) {
        // Containers pause through their runtime, like Stop. All of them share
        // the helper's pid, so they're matched by container, not by process.
        if let container = server.container {
            guard container.isRunning else { start(server); return }
            guard confirm(server.isPaused ? "Resume" : "Pause", server: server) else { return }
            let done = containerCompletion(container)
            if server.isPaused { DockerEngine.resume(container, completion: done) } else { DockerEngine.pause(container, completion: done) }
            return
        }
        guard confirm(server.isPaused ? "Resume" : "Pause", server: server) else { return }
        if let reason = ProcessControl.validate(server) { actionError = reason; return }
        let ok = server.isPaused ? ProcessControl.resume(server) : ProcessControl.pause(server)
        guard ok else { actionError = "The process could not be paused or resumed safely."; return }
        // Show it now rather than at the next scan. Ports served by one process pause together.
        for index in servers.indices where servers[index].rootPid == server.rootPid {
            servers[index].isPaused = !server.isPaused
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scan() }
    }

    // MARK: - Ports and processes

    func setPortRange(min: Int, max: Int) {
        guard (1...65535).contains(min), (min...65535).contains(max) else {
            actionError = "Port range must be between 1 and 65535, with minimum no greater than maximum."
            return
        }
        minPort = min
        maxPort = max
        defaults.set(min, forKey: "minPort")
        defaults.set(max, forKey: "maxPort")
        scan()
    }

    func addToAllowlist(_ process: String) {
        allowlist.insert(process)
        saveAllowlist()
    }

    func removeFromAllowlist(_ process: String) {
        allowlist.remove(process)
        saveAllowlist()
    }

    func resetAllowlist() {
        allowlist = Self.defaultAllowlist
        saveAllowlist()
    }

    private func saveAllowlist() {
        defaults.set(Array(allowlist), forKey: "allowlist")
        scan()
    }
}
