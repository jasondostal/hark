import SwiftUI
import AVFAudio

/// "What's new": one screen, shown once to people updating, and kept under Settings > About.
enum WhatsNew {
    /// The release the card describes. Bump it, and rewrite the card, when there's something to tell people updating.
    static let version = "1.1"
    private static let key = "whatsNewSeen"

    /// True on the first launch of this release for someone who was already using Hark.
    static func isDue() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-whatsnew") { return true }       // screenshot aid
        if args.contains("-notips") { return false }
        if let seen = UserDefaults.standard.string(forKey: key) { return seen.compare(version, options: .numeric) == .orderedAscending }
        // No record. 1.0 kept none, so an update is told from a new install by the microphone prompt: someone who has
        // answered it has used Hark before. A new install has nothing to catch up on.
        if AVAudioApplication.shared.recordPermission == .undetermined { markSeen(); return false }
        return true
    }
    static func markSeen() { UserDefaults.standard.set(version, forKey: key) }
}

struct WhatsNewView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface

    private struct Item: Identifiable {
        let symbol: String, title: String, text: LocalizedStringKey
        var id: String { title }
    }
    private let items = [
        Item(symbol: "paintpalette", title: "A new look",
             text: "The whole app takes your spectrogram's colors. Prefer it light? Pick **Field Notebook** under Settings › Look, or the **Paper** spectrogram."),
        Item(symbol: "arrow.up.left.and.arrow.down.right", title: "Full screen",
             text: "Tap the arrows on the spectrogram, or turn the phone sideways. Tap a name for its buttons; flick it left if it's wrong."),
        Item(symbol: "chevron.up.chevron.down", title: "Modes",
             text: "The button above Listen picks one: **Live**, **Manual**, **Point count**, **Survey**, or **Recordings** for audio files."),
        Item(symbol: "book.pages", title: "The Log is now the Journal",
             text: "Same place, bottom left. Sessions can have names and notes."),
        Item(symbol: "slider.horizontal.3", title: "More to tune",
             text: "Spectrogram detail, microphone gain, a high-pass filter and one confidence slider, in Settings."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hark \(WhatsNew.version)").font(.caption.weight(.semibold)).kerning(1.6).textCase(.uppercase)
                        .foregroundStyle(surface.ink.opacity(0.7))
                    Text("What's new").font(theme.captionFont(40))
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 72).padding(.bottom, 4)
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(surface.accent)
                            .frame(width: 42, height: 42)
                            .background(surface.ink.opacity(0.08), in: theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Circle()))
                            .overlay { (theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Circle())).stroke(surface.ink.opacity(0.16), lineWidth: 1) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(theme.captionFont(20))
                            Text(item.text).font(.subheadline).foregroundStyle(surface.ink.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(alignment: .top) { glow }
        .background(surface.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { dismiss() } label: {
                Text("Got it").font(.headline).foregroundStyle(surface.background)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(surface.accent, in: theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Capsule()))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)
            .background(surface.background)
            .overlay(alignment: .top) {      // what scrolls under the button fades out instead of being cut
                LinearGradient(colors: [surface.background.opacity(0), surface.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22).offset(y: -22).allowsHitTesting(false)
            }
        }
        .foregroundStyle(surface.ink)
        .onAppear { WhatsNew.markSeen() }
    }

    /// The spectrogram's own colors, loud to quiet, as light at the top of the page.
    private var glow: some View {
        let palette = listener.palette
        let colors = [0.7, 0.52, 0.36, 0.2].map { t -> Color in
            let (r, g, b) = palette.color(Float(t))
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
        return LinearGradient(colors: colors + [surface.background], startPoint: .top, endPoint: .bottom)
            .frame(height: 300)
            .mask(LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
    }
}
