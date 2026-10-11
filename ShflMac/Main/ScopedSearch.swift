import Observation
import SwiftUI

/// While a screen with its own search is up, like an artist's songs, the window's search field edits it.
@Observable
@MainActor
final class ScopedSearch {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    let prompt: String
    var text = ""

    init(prompt: String) {
        self.prompt = prompt
    }
}

struct SearchScopeAction {
    private let set: (ScopedSearch?) -> Void

    init(_ set: @escaping (ScopedSearch?) -> Void) {
        self.set = set
    }

    func callAsFunction(_ search: ScopedSearch?) {
        set(search)
    }
}

extension EnvironmentValues {
    @Entry var setSearchScope = SearchScopeAction { _ in }
}

extension View {
    func searchScope(_ search: ScopedSearch) -> some View {
        modifier(SearchScopeModifier(search: search))
    }
}

private struct SearchScopeModifier: ViewModifier {
    let search: ScopedSearch

    @Environment(\.setSearchScope) private var setSearchScope

    func body(content: Content) -> some View {
        content
            .onAppear { setSearchScope(search) }
            .onDisappear { setSearchScope(nil) }
    }
}
