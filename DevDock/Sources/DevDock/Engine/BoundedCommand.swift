import Darwin
import Foundation

enum BoundedCommand {
    static func run(_ executable: String, _ arguments: [String], directory: String? = nil,
                    timeout: TimeInterval = 5, limit: Int = 4 * 1024 * 1024,
                    environment: [String: String]? = nil) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let identity = ProcessInspector.snapshot(process.processIdentifier)
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { data.append(buffer, count: count) }
            if count == 0 { break }
            if count < 0 && errno != EAGAIN && errno != EINTR { return nil }
            if data.count > limit || ProcessInfo.processInfo.systemUptime >= deadline {
                if let identity, ProcessInspector.snapshot(identity.pid)?.startTime == identity.startTime {
                    _ = kill(identity.pid, SIGKILL)
                }
                return nil
            }
            if count < 0 { var pending = pollfd(fd: fd, events: Int16(POLLIN), revents: 0); _ = poll(&pending, 1, 25) }
        }
        // stdout may close before the child exits. Bound that wait too.
        while process.isRunning {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                if let identity, ProcessInspector.snapshot(identity.pid)?.startTime == identity.startTime { _ = kill(identity.pid, SIGKILL) }
                return nil
            }
            usleep(10_000)
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
