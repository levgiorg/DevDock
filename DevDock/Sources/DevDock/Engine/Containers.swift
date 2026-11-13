import Darwin
import Foundation

/// A container runtime on this Mac: a helper process that holds the ports
/// containers publish, and the Docker Engine API socket that knows which
/// container owns each port. Stopping the helper would take every container
/// down with it, so container rows never signal it.
struct ContainerRuntime: Hashable {
    /// Shown on container rows: OrbStack, Docker, Colima, Rancher Desktop.
    let name: String
    let socketPath: String
    /// The app whose own memory already includes its containers' VM.
    var appBundle: String?

    static func orbStack(home: String = Self.home) -> ContainerRuntime {
        ContainerRuntime(name: "OrbStack", socketPath: home + "/.orbstack/run/docker.sock", appBundle: "OrbStack.app")
    }

    static func dockerDesktop(home: String = Self.home) -> ContainerRuntime {
        ContainerRuntime(name: "Docker", socketPath: home + "/.docker/run/docker.sock", appBundle: "Docker.app")
    }

    /// Recognises a runtime's port helper. OrbStack and Docker Desktop are found
    /// by executable, since the kernel truncates names like `com.docker.backend`.
    /// Colima and Rancher Desktop forward ports through Lima, with `ssh` or
    /// `limactl hostagent` processes whose arguments name the Lima instance;
    /// a plain `ssh` tunnel never matches.
    static func owning(executablePath path: String, arguments: [String], home: String = Self.home) -> ContainerRuntime? {
        if path.contains("/OrbStack.app/") { return .orbStack(home: home) }
        if path.contains("/Docker.app/") { return .dockerDesktop(home: home) }
        let tool = (path as NSString).lastPathComponent
        guard tool == "ssh" || tool == "limactl" else { return nil }
        let joined = arguments.joined(separator: " ")
        if let range = joined.range(of: "/.colima/_lima/") {
            // Lima instance `colima` is Colima's default profile, `colima-work` is profile `work`.
            let instance = joined[range.upperBound...].prefix { $0 != "/" && $0 != " " }
            let profile = instance == "colima" ? "default" : String(instance.dropFirst("colima-".count))
            guard instance.hasPrefix("colima"), !profile.isEmpty else { return nil }
            let name = profile == "default" ? "Colima" : "Colima \(profile)"
            return ContainerRuntime(name: name, socketPath: home + "/.colima/\(profile)/docker.sock")
        }
        if joined.contains("/rancher-desktop/lima/") {
            return ContainerRuntime(name: "Rancher Desktop", socketPath: home + "/.rd/docker.sock", appBundle: "Rancher Desktop.app")
        }
        return nil
    }

    /// Only known local Unix sockets are discovered; never use a remote Docker context.
    static func available() -> Set<ContainerRuntime> {
        var candidates: [ContainerRuntime] = [.dockerDesktop(), .orbStack(),
            ContainerRuntime(name: "Rancher Desktop", socketPath: home + "/.rd/docker.sock", appBundle: "Rancher Desktop.app")]
        let colima = home + "/.colima"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: colima)) ?? [] {
            if !name.hasPrefix("."), name != "_lima" {
                candidates.append(ContainerRuntime(name: name == "default" ? "Colima" : "Colima \(name)",
                                                   socketPath: colima + "/" + name + "/docker.sock"))
            }
        }
        return Set(candidates.filter { DockerEngine.isLocalSocket($0.socketPath) })
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path
}

struct ContainerPortBinding: Equatable, Hashable {
    let hostIP: String
    let hostPort: Int
    let containerPort: Int
}

/// A running or stopped container with a configured TCP publication on the Mac.
struct ContainerInfo: Equatable {
    let id: String
    let name: String
    let image: String
    let runtime: ContainerRuntime
    let publishedPorts: Set<Int>
    var composeProject: String?
    var composeService: String?
    /// The folder `docker compose` ran in, from the container's labels. It can
    /// be a path inside a Linux VM that doesn't exist on the Mac.
    var workingDirectory: String?
    var isPaused = false
    var isRunning = true
    var bindings: [ContainerPortBinding] = []

    var shortID: String { String(id.prefix(12)) }

    func withImage(_ image: String) -> ContainerInfo {
        ContainerInfo(id: id, name: name, image: image, runtime: runtime, publishedPorts: publishedPorts,
                      composeProject: composeProject, composeService: composeService,
                      workingDirectory: workingDirectory, isPaused: isPaused, isRunning: isRunning, bindings: bindings)
    }

    /// `postgres:16-alpine` → `postgres`, `ghcr.io/saleor/saleor:3.22` → `saleor`.
    var imageName: String {
        let path = image.split(separator: "@").first.map(String.init) ?? image
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.split(separator: ":").first.map(String.init) ?? last
    }

    /// `ghcr.io/saleor/saleor:3.22` → `saleor:3.22`, for a row's second line.
    var shortImage: String {
        let path = image.split(separator: "@").first.map(String.init) ?? image
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// What the image runs, which decides its icon and whether it's protected.
    var service: ContainerService? { ContainerService(image: image) }

    /// Databases are protected from Clean up, like the native ones, unless the
    /// process they run was taken off the protected list. An image named on
    /// that list counts too.
    func isProtected(by names: Set<String>) -> Bool {
        if names.contains(imageName.lowercased()) { return true }
        guard let service, service.holdsData else { return false }
        return service.nativeProcesses.isEmpty || !names.isDisjoint(with: service.nativeProcesses)
    }

    /// Rows sharing a key sit under one header: a compose project, or its
    /// runtime for containers started some other way.
    var groupKey: String { "\(runtime.name)/\(composeProject ?? "")" }
}

/// Services recognised from a container's image name.
enum ContainerService: Equatable {
    case postgres, mysql, mariadb, mongodb, redis, clickhouse, sqlServer
    case otherSQL, otherNoSQL
    case nginx, rabbitmq, elastic, minio, kafka

    /// Words that mean the image is a tool for a database, not the database,
    /// like `mongo-express` or `postgres-exporter`.
    private static let tools: Set<String> = ["express", "commander", "exporter", "insight", "admin", "ui", "gui"]

    init?(image: String) {
        let path = (image.split(separator: "@").first.map(String.init) ?? image).lowercased()
        let parts = path.split(separator: "/").map { $0.split(separator: ":").first.map(String.init) ?? String($0) }
        guard let name = parts.last else { return nil }
        // `mcr.microsoft.com/mssql/server` names the database in its namespace.
        if parts.dropLast().contains("mssql") { self = .sqlServer; return }
        let words = Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard words.isDisjoint(with: Self.tools) else { return nil }
        func has(_ names: String...) -> Bool { !words.isDisjoint(with: names) }
        if has("postgres", "postgresql", "postgis", "pgvector", "timescaledb") { self = .postgres }
        else if has("mysql") { self = .mysql }
        else if has("mariadb") { self = .mariadb }
        else if has("mongo", "mongodb") { self = .mongodb }
        else if has("redis") { self = .redis }
        else if has("clickhouse") { self = .clickhouse }
        else if has("mssql") { self = .sqlServer }
        else if has("cockroach", "cockroachdb", "yugabyte") { self = .otherSQL }
        else if has("valkey", "keydb", "couchdb", "cassandra", "neo4j") { self = .otherNoSQL }
        else if has("nginx") { self = .nginx }
        else if has("rabbitmq") { self = .rabbitmq }
        else if has("elasticsearch", "opensearch") { self = .elastic }
        else if has("minio") { self = .minio }
        else if has("kafka") { self = .kafka }
        else { return nil }
    }

    var holdsData: Bool {
        switch self {
        case .nginx, .rabbitmq, .elastic, .minio, .kafka: return false
        default: return true
        }
    }

    /// The native processes on the protected list that stand for this service.
    /// Empty means the list has no entry for it, so it's always protected.
    var nativeProcesses: Set<String> {
        switch self {
        case .postgres: return ["postgres"]
        case .mysql, .mariadb: return ["mysqld", "mysql"]
        case .mongodb: return ["mongod"]
        case .redis: return ["redis-server"]
        default: return []
        }
    }
}

/// Cumulative usage, in the same units the process inspector reports.
struct ContainerUsage: Equatable {
    let memory: UInt64
    let cpuNanoseconds: UInt64
}

/// A minimal Docker Engine API client over the runtime's unix socket. Menu bar
/// apps don't get the shell's PATH, so this avoids depending on the CLI.
enum DockerEngine {
    static func containers(_ runtime: ContainerRuntime) -> [ContainerInfo]? {
        guard let body = request("GET", "/containers/json?all=true", runtime: runtime, timeout: 5),
              let list = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return nil }
        guard list.count <= 512 else { return nil }
        return list.compactMap { item in
            var json = item
            guard let id = json["Id"] as? String, isValidID(id) else { return nil as ContainerInfo? }
            // Stopped containers often omit Ports in the list. Inspect only their
            // configured bindings, without exposing Config.Env or mounts to the UI.
            if json["State"] as? String != "running", json["State"] as? String != "paused" {
                guard let body = request("GET", "/containers/\(id)/json", runtime: runtime),
                      let inspect = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
                json["Ports"] = configuredPorts(inspect)
            }
            guard let container = parseContainer(json, runtime: runtime) else { return nil }
            if container.image.hasPrefix("sha256:"), let configured = configuredImage(container.id, runtime: runtime) {
                return container.withImage(configured)
            }
            return container
        }
    }

    static func configuredPorts(_ inspect: [String: Any]) -> [[String: Any]] {
        let host = inspect["HostConfig"] as? [String: Any] ?? [:]
        let ports = host["PortBindings"] as? [String: [[String: Any]]] ?? [:]
        return ports.flatMap { key, bindings -> [[String: Any]] in
            let parts = key.split(separator: "/")
            guard parts.count == 2, parts[1] == "tcp", let privatePort = Int(parts[0]) else { return [] }
            return bindings.compactMap { binding in
                guard let value = binding["HostPort"] as? String, let port = Int(value) else { return nil }
                return ["PrivatePort": privatePort, "PublicPort": port, "IP": binding["HostIp"] as? String ?? "", "Type": "tcp"]
            }
        }
    }

    private static func configuredImage(_ id: String, runtime: ContainerRuntime) -> String? {
        guard let body = request("GET", "/containers/\(id)/json", runtime: runtime),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return parseConfiguredImage(json)
    }

    static func parseConfiguredImage(_ inspect: [String: Any]) -> String? {
        (inspect["Config"] as? [String: Any])?["Image"] as? String
    }

    static func usage(_ id: String, runtime: ContainerRuntime) -> ContainerUsage? {
        guard let body = request("GET", "/containers/\(id)/stats?stream=false&one-shot=true", runtime: runtime),
              let stats = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return parseUsage(stats)
    }

    static func startedAt(_ id: String, runtime: ContainerRuntime) -> Date? {
        guard let body = request("GET", "/containers/\(id)/json", runtime: runtime),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let state = json["State"] as? [String: Any],
              let started = state["StartedAt"] as? String else { return nil }
        return parseDate(started)
    }

    enum Action: String { case start, stop, restart, pause, unpause }
    typealias Transport = (String, String, ContainerRuntime, Int) -> Data?

    static func isValidID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Re-inspect the immutable full ID and state before every mutation. Never
    /// resolve a container by name, a port alone, or a shortened ID.
    static func perform(_ action: Action, on container: ContainerInfo, transport: Transport = request) -> Bool {
        guard isValidID(container.id),
              let data = transport("GET", "/containers/\(container.id)/json", container.runtime, 2),
              let current = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              current["Id"] as? String == container.id,
              current["Name"] as? String == "/" + container.name,
              let state = current["State"] as? [String: Any],
              let running = state["Running"] as? Bool,
              let paused = state["Paused"] as? Bool,
              running == container.isRunning, paused == container.isPaused else { return false }
        let configured = configuredPorts(current).compactMap { $0["PublicPort"] as? Int }.filter { (1...65535).contains($0) }
        guard Set(configured) == container.publishedPorts else { return false }
        switch action {
        case .start: guard !running else { return false }
        case .stop, .restart: guard running else { return false }
        case .pause: guard running && !paused else { return false }
        case .unpause: guard running && paused else { return false }
        }
        if paused && (action == .stop || action == .restart) {
            guard transport("POST", "/containers/\(container.id)/unpause", container.runtime, 5) != nil else { return false }
        }
        let suffix = action == .stop || action == .restart ? "?t=10" : ""
        return transport("POST", "/containers/\(container.id)/\(action.rawValue)\(suffix)", container.runtime, 15) != nil
    }

    static func start(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) { post(.start, container, completion: completion) }
    static func stop(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) { post(.stop, container, completion: completion) }
    static func restart(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) { post(.restart, container, completion: completion) }
    static func pause(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) { post(.pause, container, completion: completion) }
    static func resume(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) { post(.unpause, container, completion: completion) }

    private static func post(_ action: Action, _ container: ContainerInfo, completion: ((Bool) -> Void)?) {
        DispatchQueue.global().async {
            let ok = perform(action, on: container)
            if let completion { DispatchQueue.main.async { completion(ok) } }
        }
    }

    // MARK: - Parsing

    static func parseContainer(_ json: [String: Any], runtime: ContainerRuntime) -> ContainerInfo? {
        guard let id = json["Id"] as? String, isValidID(id) else { return nil }
        let bindings = (json["Ports"] as? [[String: Any]] ?? []).compactMap { port -> ContainerPortBinding? in
            guard port["Type"] as? String == "tcp", let publicPort = port["PublicPort"] as? Int,
                  let privatePort = port["PrivatePort"] as? Int,
                  (1...65535).contains(publicPort), (1...65535).contains(privatePort) else { return nil }
            return ContainerPortBinding(hostIP: port["IP"] as? String ?? "", hostPort: publicPort, containerPort: privatePort)
        }
        let ports = Set(bindings.map(\.hostPort))
        guard !ports.isEmpty else { return nil }
        let names = json["Names"] as? [String] ?? []
        let name = names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(id.prefix(12))
        let labels = json["Labels"] as? [String: String] ?? [:]
        return ContainerInfo(id: id, name: name, image: json["Image"] as? String ?? "", runtime: runtime,
                             publishedPorts: Set(ports),
                             composeProject: labels["com.docker.compose.project"],
                             composeService: labels["com.docker.compose.service"],
                             workingDirectory: labels["com.docker.compose.project.working_dir"],
                             isPaused: (json["State"] as? String) == "paused",
                             isRunning: ["running", "paused"].contains(json["State"] as? String ?? "running"), bindings: bindings)
    }

    /// Memory as `docker stats` counts it: usage minus reclaimable page cache.
    static func parseUsage(_ stats: [String: Any]) -> ContainerUsage? {
        guard let memory = stats["memory_stats"] as? [String: Any],
              let used = (memory["usage"] as? NSNumber)?.uint64Value, used <= 1 << 50,
              let cpu = stats["cpu_stats"] as? [String: Any],
              let total = ((cpu["cpu_usage"] as? [String: Any])?["total_usage"] as? NSNumber)?.uint64Value else { return nil }
        let details = memory["stats"] as? [String: Any] ?? [:]
        let cache = ((details["inactive_file"] ?? details["total_inactive_file"]) as? NSNumber)?.uint64Value ?? 0
        return ContainerUsage(memory: used > cache ? used - cache : used, cpuNanoseconds: total)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - HTTP over a unix socket

    /// Returns the response body for a 2xx status, otherwise nil.
    static func request(_ method: String, _ path: String, runtime: ContainerRuntime, timeout: Int = 2) -> Data? {
        guard allowedRequest(method, path) else { return nil }
        let fd = send(method, path, runtime: runtime, timeout: timeout)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeout)
        while true {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let count = recv(fd, &buffer, buffer.count, 0)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; return nil }
            guard response.count + count <= 8 * 1024 * 1024 else { return nil }
            response.append(buffer, count: count)
        }
        return parseResponse(response)
    }

    static func allowedRequest(_ method: String, _ path: String) -> Bool {
        if method == "GET", path == "/containers/json?all=true" { return true }
        guard path.utf8.count < 256 else { return false }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 4, pieces[0].isEmpty, pieces[1] == "containers", isValidID(String(pieces[2])) else { return false }
        if method == "GET" { return ["json", "stats?stream=false&one-shot=true"].contains(String(pieces[3])) }
        return method == "POST" && ["start", "stop?t=10", "restart?t=10", "pause", "unpause"].contains(String(pieces[3]))
    }

    static func isLocalSocket(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return false }
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid() || info.st_uid == 0 else { return false }
        return true
    }

    /// Connects to the runtime's socket and sends an HTTP/1.0 request, so the
    /// engine answers without chunking and closes when it's done.
    private static func send(_ method: String, _ path: String, runtime: ContainerRuntime, timeout: Int, readTimeout: Int? = nil) -> Int32 {
        guard isLocalSocket(runtime.socketPath), allowedRequest(method, path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var sendTime = timeval(tv_sec: timeout, tv_usec: 0)
        var readTime = timeval(tv_sec: readTimeout ?? timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTime, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTime, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(runtime.socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { close(fd); return -1 }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { close(fd); return -1 }
            var pending = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&pending, 1, Int32(timeout * 1000)) > 0,
                  getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { close(fd); return -1 }
        }
        guard fcntl(fd, F_SETFL, flags) == 0 else { close(fd); return -1 }
        let message = "\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let sent = message.utf8CString.withUnsafeBufferPointer { Darwin.send(fd, $0.baseAddress, $0.count - 1, 0) }
        guard sent == message.utf8.count else { close(fd); return -1 }
        return fd
    }

    /// Container events that change which containers are running.
    static let listChangingActions: Set<String> = ["start", "restart", "die", "stop", "kill", "destroy", "pause", "unpause"]

    static func parseEvent(_ line: Data) -> (action: String, id: String, time: Date)? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let action = json["Action"] as? String ?? json["status"] as? String,
              let id = (json["Actor"] as? [String: Any])?["ID"] as? String ?? json["id"] as? String else { return nil }
        let time = (json["time"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        return (action, id, time)
    }

    static func parseResponse(_ response: Data) -> Data? {
        guard response.count <= 8 * 1024 * 1024,
              let split = response.range(of: Data("\r\n\r\n".utf8)), split.lowerBound <= 16 * 1024,
              let head = String(data: response[..<split.lowerBound], encoding: .ascii) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let statusLine = lines[0].split(separator: " ")
        guard statusLine.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(statusLine[0]),
              let status = Int(statusLine[1]), (200..<300).contains(status) else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { return nil }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = Data(response[split.upperBound...])
        if let transfer = headers["transfer-encoding"] {
            guard transfer.lowercased() == "chunked", headers["content-length"] == nil else { return nil }
            return dechunk(body)
        }
        if let length = headers["content-length"] {
            guard let length = Int(length), length >= 0, body.count == length else { return nil }
        }
        return body
    }

    private static func dechunk(_ data: Data) -> Data? {
        var result = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while index < data.endIndex {
            guard let line = data.range(of: crlf, in: index..<data.endIndex),
                  let text = String(data: data[index..<line.lowerBound], encoding: .ascii),
                  let token = text.split(separator: ";").first, !token.isEmpty,
                  token.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let size = Int(token, radix: 16), size >= 0, size <= data.count else { return nil }
            let start = line.upperBound
            if size == 0 { return Data(data[start...]) == crlf ? result : nil }
            guard let end = data.index(start, offsetBy: size, limitedBy: data.endIndex),
                  let next = data.index(end, offsetBy: 2, limitedBy: data.endIndex), data[end..<next] == crlf else { return nil }
            result.append(data[start..<end])
            index = next
        }
        return nil
    }
}
