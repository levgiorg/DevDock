import Darwin
import Foundation

/// The `wtp` command: a user-owned symlink to this app's executable,
/// which runs the terminal UI when invoked by that name. Linking the app's
/// path rather than a copy keeps it current through updates.
enum CommandLineTool {
    static let linkPath = NSHomeDirectory() + "/.local/bin/wtp"

    enum State: Equatable {
        /// Not running from a stable app bundle, e.g. `swift run` or a translocated download.
        case unavailable
        case notInstalled
        case installed
        /// Something else is at the link path: another copy, a missing app or a different tool.
        case other(String)
    }

    /// Only an app bundle at a stable location can be linked to.
    static var executablePath: String? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              !path.contains("/AppTranslocation/") else { return nil }
        return path
    }

    static var state: State {
        guard let target = executablePath else { return .unavailable }
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkPath) else {
            return fileManager.fileExists(atPath: linkPath) ? .other(linkPath) : .notInstalled
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: (linkPath as NSString).deletingLastPathComponent, isDirectory: true))
            .resolvingSymlinksInPath().path
        return resolved == target ? .installed : .other(resolved)
    }

    /// Installs without administrator privileges or replacing another command.
    static func install() -> String? {
        guard let target = executablePath else { return "Move DevDock to Applications first." }
        return installLink(target: target, home: NSHomeDirectory())
    }

    /// Injectable home keeps filesystem regression tests isolated from the real CLI.
    static func installLink(target: String, home: String) -> String? {
        guard target.hasPrefix("/"), home.hasPrefix("/"), !target.utf8.contains(0), !home.utf8.contains(0) else {
            return "The command and home paths must be absolute."
        }
        let fm = FileManager.default
        let path = home + "/.local/bin/wtp"
        let directory = (path as NSString).deletingLastPathComponent
        do {
            for path in [home + "/.local", directory] {
                if !fm.fileExists(atPath: path) { try fm.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755]) }
                let attrs = try fm.attributesOfItem(atPath: path)
                guard attrs[.type] as? FileAttributeType == .typeDirectory,
                      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0 else {
                    return "The command directory must be a user-owned directory without group or other write access."
                }
            }
            if (try? fm.destinationOfSymbolicLink(atPath: path)) == target { return nil }
            // symlink fails atomically with EEXIST; never unlink a pre-existing tool.
            try fm.createSymbolicLink(atPath: path, withDestinationPath: target)
            return nil
        } catch { return "The command could not be installed. An existing command will not be replaced." }
    }

    static func uninstall() -> String? {
        guard state == .installed else { return nil }
        do { try FileManager.default.removeItem(atPath: linkPath); return nil }
        catch { return "The command could not be removed." }
    }
}
