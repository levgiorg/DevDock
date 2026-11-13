import SwiftUI

/// Apply English system controls and a consistent left-to-right layout.
struct LocalizedView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().environment(\.locale, L10n.locale).environment(\.layoutDirection, .leftToRight)
    }
}
