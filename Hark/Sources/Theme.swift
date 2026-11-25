import SwiftUI
import UIKit
import HarkCore

/// Whole-app looks (Settings > Look). Each sets the colors, type, row icons, Listen button and a matching
/// spectrogram palette; the palette stays pickable on its own afterwards. Hark's own look (stored as "classic")
/// has no colors of its own: it takes them from the spectrogram's palette, so the whole app follows the picture.
/// The pixel and stencil faces are only for names and headings: small print stays in the system font.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic, night, arcade, owling, notebook, blind
    var id: String { rawValue }

    static var stored: AppTheme { AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .classic }

    var title: String {
        switch self {
        case .classic: "Hark"; case .night: "Night Sky"; case .arcade: "8-bit"; case .owling: "Owling"; case .notebook: "Field Notebook"; case .blind: "Duck Blind"
        }
    }
    var blurb: String {
        switch self {
        case .classic: "Colors come from the spectrogram you pick, with a field-guide serif for names."
        case .night: "The icon's night sky: indigo, mint and a glowing Listen button."
        case .arcade: "Pixel critters, square buttons and the 8-bit spectrogram."
        case .owling: "Everything red on black, so you keep your night vision."
        case .notebook: "Cream paper, ink, a field-guide serif and a pencil spectrogram."
        case .blind: "Marsh and cattail tones with a dawn spectrogram."
        }
    }
    /// The spectrogram colors that come with the look.
    var palette: SpectrogramPalette {
        switch self {
        case .classic, .night: .aurora; case .arcade: .arcade; case .owling: .owling; case .notebook: .paper; case .blind: .dawn
        }
    }
    var scheme: ColorScheme? { switch self { case .classic: nil; case .notebook: .light; default: .dark } }
    var isPixel: Bool { self == .arcade }

    // MARK: Colors (nil = from the spectrogram's palette, see `surface`)

    var background: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0x0D0A22); case .arcade: Color(hex: 0x0E0924)
        case .owling: .black; case .notebook: Color(hex: 0xEFE6D2); case .blind: Color(hex: 0x2B2A1F)
        }
    }
    var card: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0x1A143C); case .arcade: Color(hex: 0x1B1240)
        case .owling: Color(hex: 0x140303); case .notebook: Color(hex: 0xF8F1E1); case .blind: Color(hex: 0x3A3828)
        }
    }
    var ink: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0xECF8F1); case .arcade: Color(hex: 0xF0FFF4)
        case .owling: Color(hex: 0xFF4A33); case .notebook: Color(hex: 0x2E2418); case .blind: Color(hex: 0xEFE6C8)
        }
    }
    var accent: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0x5FE0A0); case .arcade: Color(hex: 0x3FCF8E)
        case .owling: Color(hex: 0xFF4A33); case .notebook: Color(hex: 0x8A5A2B); case .blind: Color(hex: 0xD9A441)
        }
    }
    /// Seals, "Both models", "I saw it".
    var good: Color? {
        switch self {
        case .classic: nil; case .night, .arcade: Color(hex: 0x5FE0A0); case .owling: Color(hex: 0xFF4A33); case .notebook: Color(hex: 0x4F7A3A); case .blind: Color(hex: 0xA3C45A)
        }
    }
    var celebrate: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0xA8F2C8); case .arcade: Color(hex: 0xF0D878)
        case .owling: Color(hex: 0xFF4A33); case .notebook: Color(hex: 0x8A5A2B); case .blind: Color(hex: 0xD9A441)
        }
    }
    /// Bottom bar and landscape rail.
    var bar: Color? {
        switch self {
        case .classic: nil; case .night: Color(hex: 0x120E2C); case .arcade: Color(hex: 0x160F36)
        case .owling: Color(hex: 0x070000); case .notebook: Color(hex: 0xE7DCC3); case .blind: Color(hex: 0x24231A)
        }
    }
    var cardBorder: Color? {
        switch self {
        case .arcade: Color(hex: 0x3A2A78); case .night: Color(hex: 0xA08CFF).opacity(0.14); default: nil
        }
    }

    func tint(_ g: TaxonGroup) -> Color {
        switch self {
        case .classic:
            switch g {
            case .bird: .blue; case .amphibian: .green; case .insect: .orange; case .mammal: .brown
            case .reptile: .mint; case .fish: .cyan; case .sound: .gray; case .other, .unknown: .purple
            }
        case .night:
            switch g {
            case .bird: Color(hex: 0x7FB8FF); case .amphibian: Color(hex: 0x5FE0A0); case .insect: Color(hex: 0xFFC46B)
            case .mammal: Color(hex: 0xD6A679); case .reptile: Color(hex: 0x6FE3D6); case .fish: Color(hex: 0x7FDCFF)
            case .sound: Color(hex: 0xA5A0C8); case .other, .unknown: Color(hex: 0xB79CFF)
            }
        case .arcade:
            switch g {
            case .bird: Color(hex: 0xE2323A); case .amphibian: Color(hex: 0xA6A050); case .insect: Color(hex: 0xF0D878)
            case .mammal: Color(hex: 0xC47A36); case .reptile: Color(hex: 0x5FE0A0); case .fish: Color(hex: 0x6AD0FF)
            case .sound: Color(hex: 0x9D8FD6); case .other, .unknown: Color(hex: 0xC9A8FF)
            }
        case .owling: g == .sound ? Color(hex: 0xA3271A) : Color(hex: 0xFF4A33)
        case .notebook:
            switch g {
            case .bird: Color(hex: 0x3F5F7F); case .amphibian: Color(hex: 0x4F7A3A); case .insect: Color(hex: 0x9A6A24)
            case .mammal: Color(hex: 0x7A5236); case .reptile: Color(hex: 0x56785A); case .fish: Color(hex: 0x3F7480)
            case .sound: Color(hex: 0x8A7A62); case .other, .unknown: Color(hex: 0x65558A)
            }
        case .blind:
            switch g {
            case .bird: Color(hex: 0xD9A441); case .amphibian: Color(hex: 0xA3C45A); case .insect: Color(hex: 0xE3C06A)
            case .mammal: Color(hex: 0xC08A5A); case .reptile: Color(hex: 0x8FB07A); case .fish: Color(hex: 0x7FA3A0)
            case .sound: Color(hex: 0xB3A982); case .other, .unknown: Color(hex: 0xB39A7A)
            }
        }
    }

    // MARK: Type

    var fontDesign: Font.Design? { switch self { case .night: .rounded; case .notebook: .serif; default: nil } }

    /// Species names.
    func nameFont(_ style: Font.TextStyle) -> Font {
        switch self {
        case .arcade: .custom("Silkscreen-Regular", size: Self.pixelSize(style), relativeTo: style)
        case .night: .system(style, design: .rounded, weight: style == .headline ? .heavy : .bold)
        case .notebook, .classic: .system(style, design: .serif, weight: style == .title2 ? .bold : .semibold)
        default: .system(style, weight: style == .title2 ? .bold : nil)
        }
    }
    /// Section headers and the celebration line.
    func headerFont(_ style: Font.TextStyle = .subheadline) -> Font? {
        switch self {
        case .arcade: .custom("Silkscreen-Regular", size: Self.pixelSize(style), relativeTo: style)
        case .blind: .custom("SairaStencilOne-Regular", size: style == .subheadline ? 16 : 20, relativeTo: style)
        case .night: .system(style, design: .rounded, weight: .heavy)
        case .notebook: .system(style == .subheadline ? .headline : style, design: .serif, weight: .semibold).italic()
        case .classic: .system(style == .subheadline ? .caption : style, weight: .semibold)      // small, spaced capitals
        default: nil
        }
    }
    /// Silkscreen runs wide: about three quarters of the system size reads the same.
    private static func pixelSize(_ s: Font.TextStyle) -> CGFloat {
        switch s {
        case .largeTitle: 26; case .title: 22; case .title2: 18; case .title3: 16; case .headline, .body: 13
        case .callout, .subheadline: 12; default: 10
        }
    }
    var navTitleFont: UIFont? {
        switch self {
        case .arcade: UIFont(name: "Silkscreen-Regular", size: 15)
        case .blind: UIFont(name: "SairaStencilOne-Regular", size: 19)
        case .night: UIFont.systemFont(ofSize: 17, weight: .heavy).withDesign(.rounded)
        case .notebook, .classic: UIFont.systemFont(ofSize: 17, weight: .semibold).withDesign(.serif)
        default: nil
        }
    }
    var navLargeTitleFont: UIFont? {
        switch self {
        case .arcade: UIFont(name: "Silkscreen-Regular", size: 28)
        case .blind: UIFont(name: "SairaStencilOne-Regular", size: 34)
        case .night: UIFont.systemFont(ofSize: 34, weight: .heavy).withDesign(.rounded)
        case .notebook, .classic: UIFont.systemFont(ofSize: 34, weight: .bold).withDesign(.serif)
        default: nil
        }
    }

    // MARK: Icons

    /// The pixel critter for a group (8-bit look), from design/icons/pixel/sprites.py.
    static func sprite(_ g: TaxonGroup) -> String? {
        switch g {
        case .bird: "px-bird"; case .amphibian: "px-toad"; case .insect: "px-cricket"; case .mammal: "px-chipmunk"
        default: nil
        }
    }

    /// Navigation titles are UIKit: set them for bars created from now on.
    func applyAppearance(ink: Color) {
        let nav = UINavigationBar.appearance()
        var small: [NSAttributedString.Key: Any] = [:], large: [NSAttributedString.Key: Any] = [:]
        if let f = navTitleFont { small[.font] = f }
        if let f = navLargeTitleFont { large[.font] = f }
        small[.foregroundColor] = UIColor(ink); large[.foregroundColor] = UIColor(ink)
        nav.titleTextAttributes = small.isEmpty ? nil : small
        nav.largeTitleTextAttributes = large.isEmpty ? nil : large
    }
}

extension UIFont {
    func withDesign(_ d: UIFontDescriptor.SystemDesign) -> UIFont {
        fontDescriptor.withDesign(d).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry var theme: AppTheme = .classic
    /// What this part of the app is drawn on and in (set by `themeRoot`, and again over the spectrogram in full screen).
    @Entry var surface: Surface = SpectrogramPalette.aurora.surface
}

/// What a screen is drawn on and in: the colors everything on it takes. A named look brings its own; Hark's own
/// look takes them from the spectrogram's palette.
struct Surface: Equatable {
    var background: Color
    /// Grouped rows in the sheets (the Journal, Settings).
    var card: Color
    var cardBorder: Color?
    var ink: Color
    var accent: Color
    /// Bottom bar and landscape rail.
    var bar: Color
    /// Seals, "Both models", "I saw it".
    var good: Color
    /// "New for you".
    var celebrate: Color
    var scheme: ColorScheme
}

extension AppTheme {
    /// The look's colors, with the spectrogram's filling in whatever the look leaves open.
    func surface(_ palette: SpectrogramPalette) -> Surface {
        let p = palette.surface
        return Surface(background: background ?? p.background, card: card ?? p.card, cardBorder: cardBorder, ink: ink ?? p.ink,
                       accent: accent ?? p.accent, bar: bar ?? p.bar, good: good ?? p.good, celebrate: celebrate ?? p.celebrate,
                       scheme: scheme ?? p.scheme)
    }
}

// MARK: Styles that follow the look

/// The look's "good" color (seals, "I saw it").
struct GoodStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.good }
}
struct CelebrateStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.celebrate }
}
/// Screen background.
struct AppBackgroundStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.background }
}
/// Bottom bar / rail.
struct AppBarStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.bar }
}
/// The surface's text color, straight (`.primary` follows it too, wherever `themeRoot` set it).
struct InkStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.ink }
}
/// The surface's bright color.
struct AccentStyle: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.surface.accent }
}
extension ShapeStyle where Self == GoodStyle { static var good: GoodStyle { GoodStyle() } }
extension ShapeStyle where Self == CelebrateStyle { static var celebrate: CelebrateStyle { CelebrateStyle() } }
extension ShapeStyle where Self == AppBackgroundStyle { static var appBackground: AppBackgroundStyle { AppBackgroundStyle() } }
extension ShapeStyle where Self == AppBarStyle { static var appBar: AppBarStyle { AppBarStyle() } }
extension ShapeStyle where Self == InkStyle { static var ink: InkStyle { InkStyle() } }
extension ShapeStyle where Self == AccentStyle { static var accent: AccentStyle { AccentStyle() } }

// MARK: Modifiers

/// The look, applied at the root of the app and of each sheet: environment, color scheme, tint, type, ink.
private struct ThemeRoot: ViewModifier {
    @AppStorage("theme") private var raw = AppTheme.classic.rawValue
    func body(content: Content) -> some View {
        let t = AppTheme(rawValue: raw) ?? .classic
        let s = t.surface(Listener.shared.palette)
        content
            .environment(\.theme, t)
            .environment(\.surface, s)
            .preferredColorScheme(s.scheme)
            .tint(s.accent)
            .fontDesign(t.fontDesign)
            .foregroundStyle(s.ink)
            .onAppear { t.applyAppearance(ink: s.ink) }
            .onChange(of: s) { t.applyAppearance(ink: s.ink) }
    }
}

/// A List or Form on the look's background.
private struct ThemedList: ViewModifier {
    @Environment(\.surface) private var surface
    func body(content: Content) -> some View { content.scrollContentBackground(.hidden).background(surface.background) }
}

private struct ThemedRows: ViewModifier {
    @Environment(\.surface) private var surface
    func body(content: Content) -> some View { content.listRowBackground(surface.card) }
}

/// Section headers in the look's heading face.
private struct ThemedHeader: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        if theme != .classic, let f = theme.headerFont() {
            content.font(f).textCase(theme == .arcade || theme == .blind ? .uppercase : nil)
        } else {      // small, spaced capitals
            content.font(.caption.weight(.semibold)).kerning(1.3).textCase(.uppercase)
        }
    }
}

/// Species names in the look's name face.
private struct SpeciesName: ViewModifier {
    @Environment(\.theme) private var theme
    let style: Font.TextStyle
    func body(content: Content) -> some View { content.font(theme.nameFont(style)) }
}

/// A list section titled in the look's heading face.
struct ThemedSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { Section { content } header: { Text(title).themedHeader() } }
}

extension View {
    func themeRoot() -> some View { modifier(ThemeRoot()) }
    func themedList() -> some View { modifier(ThemedList()) }
    func themedHeader() -> some View { modifier(ThemedHeader()) }
    func speciesName(_ style: Font.TextStyle = .body) -> some View { modifier(SpeciesName(style: style)) }
    /// Row background for the look's cards. Put it on a Group around a list's content.
    func themedRows() -> some View { modifier(ThemedRows()) }
}

// MARK: Pick a look

/// Settings > Look: a row of little phones, one per look.
struct ThemePicker: View {
    @Environment(Listener.self) private var listener
    @AppStorage("theme") private var raw = AppTheme.classic.rawValue
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { t in
                    Button {
                        raw = t.rawValue
                        listener.palette = t.palette
                    } label: { ThemeSwatch(theme: t, selected: raw == t.rawValue) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.title)
                    .accessibilityHint(t.blurb)
                    .accessibilityAddTraits(raw == t.rawValue ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ThemeSwatch: View {
    @Environment(Listener.self) private var listener
    let theme: AppTheme
    let selected: Bool
    var body: some View {
        // Hark's own look is drawn in the colors it would take from the spectrogram in use.
        let palette = theme == .classic && selected ? listener.palette : theme.palette
        let look = theme.surface(palette)
        let bg = look.background, card = look.card, ink = look.ink
        let square = theme.isPixel
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                Rectangle().fill(palette.gradient).frame(height: 26)
                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { i in
                        HStack(spacing: 4) {
                            if square, let s = AppTheme.sprite(i == 0 ? .bird : .amphibian) {
                                Image(s).interpolation(.none).resizable().frame(width: 9, height: 9)
                            } else {
                                Circle().fill(theme == .classic ? ink.opacity(0.5) : theme.tint(i == 0 ? .bird : .amphibian)).frame(width: 8, height: 8)
                            }
                            RoundedRectangle(cornerRadius: square ? 0 : 2).fill(ink.opacity(0.75)).frame(height: 3)
                        }
                        .padding(4)
                        .background(card, in: RoundedRectangle(cornerRadius: square ? 0 : 4))
                    }
                }
                .padding(5)
                Spacer(minLength: 0)
                listenDot.padding(.bottom, 6)
            }
            .frame(width: 64, height: 104)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: square ? 2 : 10))
            .overlay {
                RoundedRectangle(cornerRadius: square ? 2 : 10)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
            }
            Text(theme.title).font(.caption2.weight(selected ? .bold : .regular)).lineLimit(1).fixedSize()
        }
    }

    @ViewBuilder private var listenDot: some View {
        let s = ListenStyle(theme: theme)
        if theme.isPixel {
            Rectangle().fill(s.fill).frame(width: 16, height: 16).background(Rectangle().fill(s.shadow).offset(x: 2, y: 2))
        } else {
            Circle().fill(s.fill).frame(width: 16, height: 16).shadow(color: s.glow ?? .clear, radius: 4)
        }
    }
}

/// The Listen button's look.
struct ListenStyle {
    let theme: AppTheme
    var listening = false
    var fill: AnyShapeStyle {
        switch theme {
        case .classic: AnyShapeStyle(listening ? Color.red : Color.green)
        case .night: listening
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF9A8A), Color(hex: 0xE5484D), Color(hex: 0x7050C0)], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xA8F2C8), Color(hex: 0x3FCF8E), Color(hex: 0x7050C0)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .arcade: AnyShapeStyle(listening ? Color(hex: 0xE2323A) : Color(hex: 0x3FCF8E))
        case .owling: AnyShapeStyle(listening ? Color(hex: 0xFF4A33) : Color(hex: 0xB81D10))
        case .notebook: AnyShapeStyle(listening ? Color(hex: 0xA8432A) : Color(hex: 0x4F7A3A))
        case .blind: AnyShapeStyle(listening ? Color(hex: 0xB5442A) : Color(hex: 0xC9802E))
        }
    }
    var ring: Color {
        switch theme {
        case .classic: Color.primary.opacity(0.15); case .night: Color(hex: 0x5FE0A0).opacity(0.25)
        case .arcade: Color(hex: 0xF0FFF4); case .owling: Color(hex: 0x2A0705); case .notebook: Color(hex: 0xD9CBA9); case .blind: Color(hex: 0x4A4733)
        }
    }
    var glow: Color? { theme == .night ? (listening ? Color(hex: 0xE5484D) : Color(hex: 0x5FE0A0)).opacity(0.55) : nil }
    /// 8-bit: the hard drop shadow under the square button.
    var shadow: Color { listening ? Color(hex: 0x7A1A20) : Color(hex: 0x1F7A55) }
    var glyph: Color { theme == .owling ? .black : .white }
}
