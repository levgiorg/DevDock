import Foundation

/// Compatibility hooks for UI actions. This build has no telemetry transport or queue.
enum Usage {
    enum Feature: String, CaseIterable {
        case active             // The app ran
        case popover            // Opened the popover
        case shortcut           // Opened it with ⌥⌘P
        case details            // Opened a server's details
        case openBrowser = "open-browser"
        case openEditor = "open-editor"
        case stop
        case pause
        case restart
        case cleanUp = "clean-up"
        case autoCleanUp = "auto-clean-up"
        case memoryAlert = "memory-alert"
        case resumeSession = "resume-session"
        case vercelPreview = "vercel-preview"
        case pullRequest = "pull-request"
    }

    static var isSharing: Bool { false }
    static func record(_ feature: Feature) {}
    static func start() { setSharing(false) }
    static func setSharing(_ enabled: Bool) {
        UserDefaults.standard.set(false, forKey: Preferences.shareUsage)
        UserDefaults.standard.removeObject(forKey: "usage.pending")
        UserDefaults.standard.removeObject(forKey: "usage.lastSent")
    }
}
