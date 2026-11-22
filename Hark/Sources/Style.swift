import SwiftUI
import HarkCore

/// Spectrogram color schemes. Index 0 is the background; levels run quiet -> loud.
enum SpectrogramPalette: String, CaseIterable, Identifiable {
    case aurora, ocean, magma, viridis, owling, grayscale, paper, arcade, dawn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: "Aurora"; case .ocean: "Ocean"; case .magma: "Magma"; case .viridis: "Viridis"
        case .owling: "Owling"; case .grayscale: "Night"; case .paper: "Paper"; case .arcade: "8-bit"; case .dawn: "Dawn"
        }
    }
    /// 8-bit: chunky blocks, a handful of flat colors, a pixel font, steps instead of smooth scrolling.
    var isPixel: Bool { self == .arcade }
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
        // the pixel icons' night: indigo, violet, green, mint, white, flat steps
        case .arcade: [(0.055, 0.035, 0.14), (0.17, 0.10, 0.37), (0.44, 0.31, 0.75), (0.25, 0.81, 0.56), (0.66, 0.95, 0.78), (0.96, 1.0, 0.96)]
        // first light over the marsh: dark reeds, ember, amber, a pale sky at the loudest
        case .dawn: [(0.05, 0.047, 0.03), (0.20, 0.15, 0.12), (0.48, 0.25, 0.16), (0.79, 0.50, 0.18), (0.95, 0.77, 0.43), (1.0, 0.94, 0.80)]
        }
    }
    func color(_ t: Float) -> (UInt8, UInt8, UInt8) {
        if isPixel {   // flat steps; quiet stays background so the blocks don't fizz, and white is only the loudest
            let s = stops, t = min(max(t, 0), 1)
            let i = [0.36, 0.50, 0.63, 0.77, 0.92].lastIndex(where: { t >= $0 }).map { $0 + 1 } ?? 0
            return (UInt8(s[i].0 * 255), UInt8(s[i].1 * 255), UInt8(s[i].2 * 255))
        }
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
        case .arcade: Color(red: 0.66, green: 0.95, blue: 0.78).opacity(0.85)
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
    private var _pixel = false
    private var _pixelBands = 4
    /// Mel bands per 8-bit block row: 4 (32 rows) for the short portrait panel, 2 (64 rows) for tall landscape,
    /// so blocks stay about square.
    var pixelBands: Int { lock.lock(); defer { lock.unlock() }; return _pixelBands }
    func set(panelHeight h: CGFloat) { lock.lock(); _pixelBands = h > 330 ? 2 : 4; lock.unlock() }
    /// 8-bit look: images are built in blocks (see SpectrogramDSP.pixelBlock).
    var pixel: Bool { lock.lock(); defer { lock.unlock() }; return _pixel }
    var lut: [UInt32] { lock.lock(); defer { lock.unlock() }; return _lut }
    /// dB above the noise floor that maps to full brightness. Smaller = punchier.
    var span: Float { lock.lock(); defer { lock.unlock() }; return _span }
    func set(palette: SpectrogramPalette) { let l = palette.lut; lock.lock(); _lut = l; _pixel = palette.isPixel; lock.unlock() }
    /// contrast 0 (soft, 54 dB) ... 1 (punchy, 24 dB)
    func set(contrast: Double) { lock.lock(); _span = Float(54 - 30 * min(max(contrast, 0), 1)); lock.unlock() }
}

/// A group glyph (bird, frog, bug...) in a tinted circle; in the 8-bit look, the pixel critter in a square.
struct TaxonIcon: View {
    var group: TaxonGroup
    var size: CGFloat = 34
    var faint = false
    @Environment(\.theme) private var theme
    var body: some View {
        let tint = theme.tint(group)
        Group {
            if theme.isPixel {
                Group {
                    if let s = AppTheme.sprite(group) {
                        Image(s).interpolation(.none).resizable().scaledToFit().padding(size * 0.1)
                    } else {
                        Image(symbol: group.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(tint)
                    }
                }
                .frame(width: size, height: size)
                .background(Color(hex: 0x2C1F5E).opacity(faint ? 0.5 : 1))
                .overlay { Rectangle().stroke(Color(hex: 0x3A2A78), lineWidth: 2) }
            } else {
                Image(symbol: group.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(tint.opacity(faint ? 0.08 : (theme == .classic ? 0.15 : 0.2)),
                                in: theme == .blind ? AnyShape(RoundedRectangle(cornerRadius: size * 0.3)) : AnyShape(Circle()))
            }
        }
        .opacity(faint ? 0.5 : 1)
    }
    static func tint(_ g: TaxonGroup) -> Color { AppTheme.classic.tint(g) }
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

extension Float {
    /// A Perch-scale score as the BirdNET-style percentage Hark shows (0.30 -> 75).
    var shownPercent: Int { Int((Fusion.display(self) * 100).rounded()) }
}
extension Double {
    var shownPercent: Int { Float(self).shownPercent }
}

extension Font {
    /// The 8-bit theme's pixel face (Silkscreen, OFL), at a size that keeps its pixels whole.
    static func pixel(_ size: CGFloat) -> Font { .custom("Silkscreen-Regular", fixedSize: size) }
}
