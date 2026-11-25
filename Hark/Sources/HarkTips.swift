import SwiftUI
import TipKit

/// First-run tips (TipKit): shown once, gone for good once you do the thing. The rest of the first-run help is the
/// "Hear something?" card on the Listen screen.
enum HarkTips {
    static func configure() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resettips") { try? Tips.resetDatastore() }      // and show tips even with the aids below
        else if ["-notips", "-select", "-settings", "-logtab", "-opensession"].contains(where: args.contains) { Tips.hideAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// Once you've selected something: you can hear it.
struct HearTip: Tip {
    @Parameter static var hasSelection: Bool = false
    var title: Text { Text("Hear what you picked") }
    var message: Text? { Text("Plays your selection, so you can check it's the call you meant.") }
    var image: Image? { Image(systemName: "speaker.wave.2.fill") }
    var rules: [Rule] { #Rule(Self.$hasSelection) { $0 == true } }
}
