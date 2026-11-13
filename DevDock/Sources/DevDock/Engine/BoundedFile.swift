import Darwin
import Foundation

/// Monitored projects and session stores are read-only, untrusted inputs. Refuse
/// FIFOs/devices and final-component symlinks, and never allocate an entire large file.
enum BoundedFile {
    static func read(_ path: String, limit: Int = 1_048_576, tail: Bool = false, complete: Bool = false) -> Data? {
        guard limit > 0, limit <= 8 * 1024 * 1024, !path.utf8.contains(0) else { return nil }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0,
              !complete || info.st_size <= limit else { return nil }
        let offset = tail ? max(0, info.st_size - off_t(limit)) : 0
        guard lseek(fd, offset, SEEK_SET) >= 0 else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(limit, 16 * 1024))
        while data.count < limit {
            let count = Darwin.read(fd, &buffer, min(buffer.count, limit - data.count))
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; return nil }
            data.append(buffer, count: count)
        }
        return data
    }

    static func text(_ path: String, limit: Int = 1_048_576) -> String? {
        read(path, limit: limit, complete: true).flatMap { String(data: $0, encoding: .utf8) }
    }
}
