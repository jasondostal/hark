import SwiftUI
import HarkCore

/// Spectrogram color schemes. Index 0 is the background; levels run quiet -> loud.
enum SpectrogramPalette: String, CaseIterable, Identifiable {
    case aurora, ocean, magma, viridis, owling, grayscale, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: "Aurora"; case .ocean: "Ocean"; case .magma: "Magma"; case .viridis: "Viridis"
        case .owling: "Owling"; case .grayscale: "Night"; case .paper: "Paper"
        }
    }
    var stops: [(Float, Float, Float)] {
        switch self {
        // night sky: indigo and violet low, curtain green high, pale mint at the loudest
        case .aurora: [(0.01, 0.01, 0.04), (0.12, 0.05, 0.28), (0.38, 0.10, 0.52), (0.08, 0.62, 0.42), (0.40, 0.95, 0.50), (0.88, 1.0, 0.86)]
        case .ocean: [(0.0, 0.01, 0.05), (0.02, 0.10, 0.30), (0.04, 0.34, 0.64), (0.18, 0.70, 0.90), (0.72, 0.95, 1.0), (1.0, 1.0, 1.0)]
        // red only, so it doesn't spoil night vision
        case .owling: [(0.0, 0.0, 0.0), (0.22, 0.0, 0.0), (0.55, 0.02, 0.0), (0.88, 0.08, 0.03), (1.0, 0.30, 0.20)]
        case .magma: [(0.0, 0.0, 0.02), (0.23, 0.06, 0.44), (0.55, 0.16, 0.51), (0.87, 0.32, 0.38), (0.99, 0.65, 0.40), (0.99, 0.99, 0.75)]
        case .viridis: [(0.07, 0.0, 0.15), (0.23, 0.32, 0.55), (0.13, 0.57, 0.55), (0.37, 0.79, 0.38), (0.99, 0.91, 0.14)]
        case .grayscale: [(0.0, 0.0, 0.0), (0.35, 0.35, 0.35), (1.0, 1.0, 1.0)]
        case .paper: [(1.0, 1.0, 1.0), (0.62, 0.62, 0.62), (0.0, 0.0, 0.0)]
        }
    }
    func color(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let s = stops, x = min(max(t, 0), 1) * Float(s.count - 1)
        let i = min(Int(x), s.count - 2), f = x - Float(i)
        func c(_ p: Float, _ q: Float) -> UInt8 { UInt8(max(0, min(255, (p + (q - p) * f) * 255))) }
        return (c(s[i].0, s[i + 1].0), c(s[i].1, s[i + 1].1), c(s[i].2, s[i + 1].2))
    }
    var lut: [UInt32] {
        (0..<256).map { i in let (r, g, b) = color(Float(i) / 255); return UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000 }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: (0...8).map { i in let (r, g, b) = color(Float(i) / 8)
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }, startPoint: .leading, endPoint: .trailing)
    }
    var background: Color { let (r, g, b) = color(0); return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var labelColor: Color {
        switch self {
        case .paper: .black.opacity(0.6)
        case .owling: Color(red: 1, green: 0.25, blue: 0.15).opacity(0.75)
        default: .white.opacity(0.7)
        }
    }
    /// Buttons and edges drawn over the spectrogram.
    var overlayTint: Color {
        switch self {
        case .paper: .black
        case .owling: Color(red: 1, green: 0.25, blue: 0.15)
        default: .white
        }
    }
}

/// Current spectrogram look, read from the audio thread (contrast) and render paths (colors).
final class SpectrogramStyle: @unchecked Sendable {
    static let shared = SpectrogramStyle()
    private let lock = NSLock()
    private var _lut = SpectrogramPalette.aurora.lut
    private var _span: Float = 36
    var lut: [UInt32] { lock.lock(); defer { lock.unlock() }; return _lut }
    /// dB above the noise floor that maps to full brightness. Smaller = punchier.
    var span: Float { lock.lock(); defer { lock.unlock() }; return _span }
    func set(palette: SpectrogramPalette) { let l = palette.lut; lock.lock(); _lut = l; lock.unlock() }
    /// contrast 0 (soft, 54 dB) ... 1 (punchy, 24 dB)
    func set(contrast: Double) { lock.lock(); _span = Float(54 - 30 * min(max(contrast, 0), 1)); lock.unlock() }
}

/// Emoji for the kind of animal or sound, on a soft disc tinted by group.
/// A plain group glyph (bird, frog, bug...) in a tinted circle.
struct TaxonIcon: View {
    var group: TaxonGroup
    var size: CGFloat = 34
    var faint = false
    var body: some View {
        Image(symbol: group.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Self.tint(group))
            .frame(width: size, height: size)
            .background(Self.tint(group).opacity(faint ? 0.08 : 0.15), in: Circle())
            .opacity(faint ? 0.5 : 1)
    }
    static func tint(_ g: TaxonGroup) -> Color {
        switch g {
        case .bird: .blue; case .amphibian: .green; case .insect: .orange; case .mammal: .brown
        case .reptile: .mint; case .fish: .cyan; case .sound: .gray; case .other, .unknown: .purple
        }
    }
}

extension HarkCore.Label {
    /// Labels loaded once, independent of the model (so the Log shows icons before Perch finishes loading).
    static let table: LabelTable? = Bundle.main.url(forResource: "labels", withExtension: "json").flatMap { try? LabelTable(contentsOf: $0) }
}

extension Detection {
    var inat: Int? { HarkCore.Label.table?.label(scientific: scientific)?.inat }
}

extension ListenGroup {
    var taxon: TaxonGroup {
        switch self {
        case .bird: .bird; case .amphibian: .amphibian; case .insect: .insect; case .mammal: .mammal
        case .reptile: .reptile; case .other: .other; case .sound: .sound
        }
    }
}
