import SwiftUI

extension Image {
    /// Hark's own symbols in Assets.xcassets, for animals SF Symbols lacks.
    static let customSymbols: Set<String> = ["frog.fill"]

    /// An SF Symbol, or one of Hark's custom symbols (they scale and tint the same way).
    init(symbol name: String) {
        if Self.customSymbols.contains(name) { self.init(name) } else { self.init(systemName: name) }
    }
}
