import SwiftUI
import TipKit

/// First-run tips (TipKit): each shows once, in order, and goes away for good once you do the thing it describes.
enum HarkTips {
    static func configure() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resettips") { try? Tips.resetDatastore() }      // and show tips even with the aids below
        else if ["-notips", "-select", "-settings", "-logtab", "-opensession"].contains(where: args.contains) { Tips.hideAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// 1. Once there's something on the spectrogram: touch it to pick out a call.
struct SelectTip: Tip {
    @Parameter static var listening: Bool = false
    var title: Text { Text("Pick out a call") }
    var message: Text? { Text("Touch the spectrogram to pause it, then drag across a sound. Hark identifies exactly that stretch, up to a minute back.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] { #Rule(Self.$listening) { $0 == true } }
}

/// 2. Once you've selected something: you can hear it.
struct HearTip: Tip {
    @Parameter static var hasSelection: Bool = false
    var title: Text { Text("Hear what you picked") }
    var message: Text? { Text("Plays your selection, so you can check it's the call you meant.") }
    var image: Image? { Image(systemName: "speaker.wave.2.fill") }
    var rules: [Rule] { #Rule(Self.$hasSelection) { $0 == true } }
}

/// 3. Back on the live view after a first selection: the two ways Hark can work.
struct ModeTip: Tip {
    static let selected = Tips.Event(id: "selected")
    var title: Text { Text("Auto or Manual") }
    var message: Text? { Text("Auto identifies everything it hears. Manual waits until you pick something out.") }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Rule] { #Rule(Self.selected) { $0.donations.count >= 1 } }
}
