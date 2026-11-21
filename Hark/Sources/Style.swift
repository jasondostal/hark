import SwiftUI
import HarkCore

/// Spectrogram color schemes. Index 0 is the background; levels run quiet -> loud.
enum SpectrogramPalette: String, CaseIterable, Identifiable {
    case aurora, magma, viridis, grayscale, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: "Aurora"; case .magma: "Magma"; case .viridis: "Viridis"
        case .grayscale: "Night"; case .paper: "Paper"
        }
    }
    var stops: [(Float, Float, Float)] {
        switch self {
        case .aurora: [(0.02, 0.02, 0.08), (0.10, 0.20, 0.45), (0.10, 0.55, 0.55), (0.55, 0.80, 0.30), (0.99, 0.91, 0.15)]
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
    var labelColor: Color { self == .paper ? .black.opacity(0.6) : .white.opacity(0.7) }
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
struct TaxonIcon: View {
    let emoji: String
    var group: TaxonGroup = .bird
    var size: CGFloat = 34
    var faint = false
    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.56))
            .frame(width: size, height: size)
            .background(Self.tint(group).opacity(faint ? 0.08 : 0.16), in: Circle())
            .opacity(faint ? 0.55 : 1)
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
    var icon: String { HarkCore.Label.table?.label(scientific: scientific)?.icon ?? "❔" }
    var inat: Int? { HarkCore.Label.table?.label(scientific: scientific)?.inat }
}

extension ListenGroup {
    var emoji: String {
        switch self {
        case .bird: "🐦"; case .amphibian: "🐸"; case .insect: "🦗"; case .mammal: "🐿️"
        case .reptile: "🦎"; case .other: "🕷️"; case .sound: "🔊"
        }
    }
    var taxon: TaxonGroup {
        switch self {
        case .bird: .bird; case .amphibian: .amphibian; case .insect: .insect; case .mammal: .mammal
        case .reptile: .reptile; case .other: .other; case .sound: .sound
        }
    }
}
