import Foundation

struct PullRequestInfo: Equatable {
    let number: Int
    let title: String
    let url: URL
    let state: String
}

/// Looks up optional pull requests through the installed GitHub CLI.
/// Results are cached per branch; no deployment provider is contacted.
@MainActor
final class GitHubLookup: ObservableObject {
    struct Result: Equatable {
        var pullRequest: PullRequestInfo?
    }

    @Published private(set) var results: [String: Result] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var inFlight = Set<String>()
    private let queue = DispatchQueue(label: "com.devdock.github", qos: .utility)

    nonisolated static let ghPath: String? = {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", NSHomeDirectory() + "/homebrew/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    nonisolated static var isAvailable: Bool { ghPath != nil }

    private var wantsPullRequests: Bool { UserDefaults.standard.bool(forKey: Preferences.githubPullRequests) }

    func result(for server: Server) -> Result? {
        guard let key = Self.key(for: server) else { return nil }
        return results[key]
    }

    /// Refreshes if enabled and the cached result is older than `maxAge`.
    func refresh(_ server: Server, maxAge: TimeInterval = 120) {
        guard wantsPullRequests, let gh = Self.ghPath,
              let key = Self.key(for: server), let root = server.project.root, let branch = server.project.branch,
              !inFlight.contains(key) else { return }
        if let fetched = fetchedAt[key], Date().timeIntervalSince(fetched) < maxAge { return }
        inFlight.insert(key)
        queue.async {
            var result = Result()
            result.pullRequest = Self.pullRequest(gh: gh, root: root, branch: branch)
            Task { @MainActor in
                self.results[key] = result
                self.fetchedAt[key] = Date()
                self.inFlight.remove(key)
            }
        }
    }

    private static func key(for server: Server) -> String? {
        guard let root = server.project.root, let branch = server.project.branch else { return nil }
        return root + "|" + branch
    }

    // MARK: - Queries

    nonisolated private static func pullRequest(gh: String, root: String, branch: String) -> PullRequestInfo? {
        guard let output = run(gh, ["pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", "number,title,url,state"], in: root),
              let list = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]],
              let pr = list.first, let number = pr["number"] as? Int,
              let urlString = pr["url"] as? String, let url = URL(string: urlString), safeWebURL(url) else { return nil }
        return PullRequestInfo(number: number, title: pr["title"] as? String ?? "", url: url, state: (pr["state"] as? String ?? "").capitalized)
    }

    // MARK: - Process helpers

    nonisolated private static func run(_ executable: String, _ arguments: [String], in directory: String) -> String? {
        var environment = ProcessInfo.processInfo.environment
        environment["GH_HOST"] = "github.com"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return BoundedCommand.run(executable, arguments, directory: directory, timeout: 10, environment: environment)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func safeWebURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    nonisolated static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
