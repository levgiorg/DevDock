import Foundation

/// English is the only interface language. Legacy preferences cannot enable translations.
enum InterfaceLanguage: String, CaseIterable {
    case system, english = "en"
    var label: String { "English" }
    func resolved(preferredLanguages: [String]) -> InterfaceLanguage { .english }
    var isRightToLeft: Bool { false }
}

/// Keep the existing call sites and format placeholders, without translating user data.
enum L10n {
    static var language: InterfaceLanguage { .english }
    static var locale: Locale { Locale(identifier: "en_US_POSIX") }
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "DevDock_DevDock", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    static func text(_ english: String, language: InterfaceLanguage = .english) -> String { english }
    static func counted(_ singular: String, _ plural: String, count: Int, language: InterfaceLanguage = .english) -> String {
        count == 1 ? singular : plural
    }
    static func format(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: english, locale: locale, arguments: arguments)
    }
    static func duration(_ interval: TimeInterval, short: Bool = false) -> String {
        short ? Format.shortDuration(interval) : Format.duration(interval)
    }
    static func time(_ date: Date) -> String { Format.time(date) }
}
