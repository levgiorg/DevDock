import Foundation
import Testing
@testable import DevDock

struct LocalizationTests {
    @Test func everyPreferenceResolvesToEnglish() {
        for preferred in [["zh-Hans"], ["ja-JP"], ["he-IL"], ["fr", "en"], []] {
            #expect(InterfaceLanguage.system.resolved(preferredLanguages: preferred) == .english)
            #expect(InterfaceLanguage.english.resolved(preferredLanguages: preferred) == .english)
        }
        #expect(L10n.language == .english)
        #expect(!L10n.language.isRightToLeft)
        #expect(InterfaceLanguage(rawValue: "zh-Hans") == nil)
        #expect(InterfaceLanguage.allCases.allSatisfy { $0.resolved(preferredLanguages: []) == .english })
    }

    @Test func englishStringsAndUserUnicodeArePreserved() {
        #expect(L10n.text("Settings") == "Settings")
        #expect(L10n.format("Stop %d processes", 3) == "Stop 3 processes")
        let name = "~/\u{4e2d}\u{6587}/café/feature"
        #expect(L10n.text(name) == name)
        #expect(L10n.counted("server", "servers", count: 1) == "server")
        #expect(L10n.counted("server", "servers", count: 0) == "servers")
        #expect(L10n.counted("server", "servers", count: 3) == "servers")
    }

    @Test func onlyEnglishResourcesAreBundled() throws {
        let localizations = Set(L10n.resourceBundle.localizations.map { $0.lowercased() })
        #expect(localizations == ["en"])
        let url = try #require(L10n.resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let table = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil) as? [String: String])
        #expect(table.allSatisfy { $0.key == $0.value })
    }

    @Test func unicodeTerminalNamesRetainTheirColumnWidths() {
        for name in ["Größe", "développement", "\u{4e2d}\u{6587}", "proyecto", "\u{65e5}\u{672c}"] {
            #expect(TerminalScreen.parse(Array(name.utf8)) == name.map(InputEvent.character))
            for width in 0...12 { #expect([Span(name)].fitted(to: width).width == width) }
        }
        #expect(TextWidth.of("\u{4e2d}\u{6587}") == 4)
    }
}
