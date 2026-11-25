import SwiftUI
import HarkCore

// Full screen ("the stage"): the spectrogram has the phone to itself, and everything else is drawn on it or on its own
// darkness. What's calling comes and goes as captions in the top corner, the least busy part of the picture (the
// highest pitches, the oldest sound), and what was heard earlier sinks below them, smaller and fainter. The bar and
// the rail take the spectrogram's background so the whole screen is one surface. Colors come from the spectrogram's
// palette, so the look follows whichever one is chosen.

extension SpectrogramPalette {
    /// Text and glyphs drawn straight on the spectrogram or on its background.
    var ink: Color {
        switch self {
        case .paper: Color(white: 0.08)
        case .owling: Color(red: 1, green: 0.29, blue: 0.2)
        case .arcade: Color(red: 0.94, green: 1.0, blue: 0.96)
        default: .white
        }
    }
    /// The palette's own bright color, for confidence rings, seals and the Listen button's level ring.
    var accent: Color {
        let (r, g, b) = color(self == .paper ? 0.7 : 0.78)
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    /// Materials and system styles over it: light on Paper, dark on the rest.
    var scheme: ColorScheme { self == .paper ? .light : .dark }
}

extension EnvironmentValues {
    /// Set on chrome that sits on the spectrogram's background in full screen: the palette to take ink from.
    @Entry var stage: SpectrogramPalette? = nil
}

extension AppTheme {
    /// Species names drawn over the spectrogram. Classic gets a field-guide serif here: over a picture, a name
    /// reads as its caption.
    func captionFont(_ size: CGFloat, strong: Bool = true) -> Font {
        switch self {
        case .arcade: .pixel(max((size * 0.6).rounded(), 8))
        case .night: .system(size: size, weight: strong ? .heavy : .bold, design: .rounded)
        case .classic, .notebook: .system(size: size, weight: strong ? .semibold : .medium, design: .serif)
        default: .system(size: size, weight: strong ? .bold : .semibold)
        }
    }
}

/// What's calling now, then maybes, then the last few species of the session, top to bottom.
/// Each caption does what a list row does: tap for its actions, flick it away for "Not it", long-press for the rest.
struct CaptionFeed: View {
    @Environment(Listener.self) private var listener
    @Environment(\.openDetection) private var open
    @Environment(\.theme) private var theme
    /// Landscape: smaller type and a shorter trail, since the phone is only so tall.
    var compact = false
    /// Show the whole session (the "and 5 more" line).
    var more: (() -> Void)?
    /// The caption whose actions are showing.
    @State private var expanded: Int?
    @State private var collapse: Task<Void, Never>?
    @State private var sharing: Detection?

    fileprivate enum Kind { case now, maybe, unusual, trail }
    fileprivate struct Item: Identifiable {
        let id: Int
        let label: HarkCore.Label
        let kind: Kind
        let confidence: Float
        var detection: Detection?
        var maybe: Maybe?
        var rank = 0
        var agreed = false
        var reason = ""
        /// The first time this species has ever been logged.
        var isNew: Bool { detection?.isFirst == true }
        var key: String { "\(id)-\(kind)-\(rank)" }
    }

    /// The captions, and how many of the session's species they leave out.
    private var feed: (items: [Item], more: Int) {
        var out: [Item] = [], seen = Set<Int>()
        let listening = listener.state == .listening
        // Newest caller on top; a bird that keeps singing holds its place (its first-heard time doesn't change).
        let now = listening ? listener.hearingNow.sorted { $0.firstHeard > $1.firstHeard } : []
        for o in now.prefix(compact ? 3 : 4) where seen.insert(o.index).inserted {
            guard let l = listener.label(o.index) else { continue }
            out.append(Item(id: o.index, label: l, kind: .now, confidence: o.bestConfidence, detection: listener.detection(for: o),
                            agreed: listener.agreed.contains(o.index)))
        }
        for m in (listening ? listener.maybes : []).prefix(2) where seen.insert(m.index).inserted {
            guard let l = listener.label(m.index) else { continue }
            out.append(Item(id: m.index, label: l, kind: m.unusual ? .unusual : .maybe, confidence: m.best, maybe: m,
                            reason: m.unusual ? listener.unusualReason(m.index) : ""))
        }
        var rank = 0
        for o in listener.session.sorted(by: { $0.lastHeard > $1.lastHeard }) where rank < (compact ? 3 : 4) && seen.insert(o.index).inserted {
            guard let l = listener.label(o.index) else { continue }
            out.append(Item(id: o.index, label: l, kind: .trail, confidence: o.bestConfidence, detection: listener.detection(for: o), rank: rank))
            rank += 1
        }
        return (out, Set(listener.session.map(\.index)).subtracting(seen).count)
    }

    var body: some View {
        let feed = feed, items = feed.items, palette = listener.palette
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            ForEach(items) { item in
                CaptionRow(item: item, compact: compact, palette: palette, expanded: expanded == item.id,
                           act: { $0(); show(nil) }, notIt: { notIt(item.id) }, open: item.detection.map { d in { open?(d) } })
                    .contentShape(Rectangle())
                    .onTapGesture { show(expanded == item.id ? nil : item.id) }
                    .modifier(Flick { notIt(item.id) })
                    .contextMenu {
                        SpeciesMenu(index: item.id, detection: item.detection, maybe: item.maybe) { sharing = $0 }
                    } preview: {
                        CaptionRow(item: item, compact: true, palette: palette, preview: true)
                            .environment(\.theme, theme)
                            .padding(.horizontal, 18).padding(.vertical, 14).background(palette.background)
                    }
                    .transition(.caption)
            }
            if feed.more > 0, let more {
                Button(action: more) {
                    HStack(spacing: 4) { Text("and \(feed.more) more"); Image(systemName: "chevron.right").imageScale(.small) }
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .padding(.leading, (compact ? 30 : 36) + 21).padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(palette.ink.opacity(0.55))
                .shadow(color: palette.background.opacity(0.9), radius: 5)
                .accessibilityLabel("\(feed.more) more species this session")
            }
        }
        .background(alignment: .topLeading) {
            // Darkens just this corner, and only while there's something to read in it.
            if !items.isEmpty {
                RadialGradient(colors: [palette.background.opacity(0.86), palette.background.opacity(0.55), palette.background.opacity(0)],
                               center: .topLeading, startRadius: 40, endRadius: compact ? 400 : 470)
                    .frame(width: 560, height: 560).offset(x: -70, y: -110)
                    .allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.6, bounce: 0.16), value: items.map(\.key))
        .animation(.snappy(duration: 0.25), value: expanded)
        .sheet(item: $sharing) { d in ShareCardSheet(detection: d).themeRoot() }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Heard")
        #if DEBUG
        .task {      // screenshot aid: -expandcaption opens the first caption's actions and leaves them open
            guard ProcessInfo.processInfo.arguments.contains("-expandcaption") else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if expanded == nil, let first = self.feed.items.first { collapse?.cancel(); expanded = first.id }
            }
        }
        #endif
    }

    /// Open one caption's actions (or none); they put themselves away after a few seconds.
    private func show(_ id: Int?) {
        collapse?.cancel()
        expanded = id
        guard id != nil else { return }
        collapse = Task { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { expanded = nil } }
    }

    private func notIt(_ index: Int) {
        show(nil)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { listener.notIt(index) }
    }
}

/// Flick a caption off to the left to say "Not it", the way you'd flick a notification away.
private struct Flick: ViewModifier {
    let action: () -> Void
    @State private var dx: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .offset(x: dx).opacity(1 - Double(min(-dx / 200, 0.75)))
            .gesture(DragGesture(minimumDistance: 14)
                .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { dx = min(v.translation.width, 0) } }
                .onEnded { v in
                    if dx < -90 || (dx < -30 && v.predictedEndTranslation.width < -220) {
                        withAnimation(.easeIn(duration: 0.16)) { dx = -340 } completion: { action(); dx = 0 }
                    } else {
                        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { dx = 0 }
                    }
                })
    }
}

/// The small buttons that open under a caption.
private struct StageChip: ButtonStyle {
    let palette: SpectrogramPalette
    var tint: Color?
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
            .foregroundStyle(tint ?? palette.ink)
            .padding(.horizontal, 11).frame(height: 32)
            .background { Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, palette.scheme) }
            .overlay { Capsule().strokeBorder((tint ?? palette.ink).opacity(0.28), lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle().inset(by: -4))
    }
}

private struct CaptionRow: View {
    @Environment(Listener.self) private var listener
    let item: CaptionFeed.Item
    let compact: Bool
    let palette: SpectrogramPalette
    /// Its actions are showing.
    var expanded = false
    /// Run an action, then put the actions away.
    var act: (() -> Void) -> Void = { $0() }
    var notIt: () -> Void = {}
    var open: (() -> Void)?
    /// Drawn in a long-press preview: full strength whatever its place in the feed.
    var preview = false
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .title2) private var scale = 1.0

    private var opacity: Double {
        if preview || expanded { return 1 }
        switch item.kind {
        case .now, .unusual: return 1
        case .maybe: return 0.7
        case .trail: return [0.74, 0.56, 0.4, 0.26][min(item.rank, 3)]
        }
    }

    var body: some View {
        let now = item.kind == .now, trail = item.kind == .trail
        let size: CGFloat = (now ? (compact ? 21 : 26) : trail ? (compact ? 14 : 15) : (compact ? 17 : 19)) * scale
        let disc: CGFloat = now ? (compact ? 30 : 36) : trail ? 20 : 26
        let column: CGFloat = (compact ? 30 : 36) + 10      // discs of every size center on one line
        let name = NameBook.shared.primary(item.label.common, item.label.scientific, species: item.label.group.isSpecies)
        let saw = item.detection?.confirmed == true
        HStack(alignment: .top, spacing: 11) {
            StageDisc(group: item.label.group, size: disc, palette: palette,
                      ring: now ? Fusion.display(item.confidence) : nil,
                      mark: item.kind == .maybe ? "questionmark.circle.fill" : item.kind == .unusual ? "exclamationmark.circle.fill" : nil)
                .frame(width: column, height: max(disc, size * 1.2) + (trail ? 0 : 12 * scale))     // level with the name and its small line
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.kind == .maybe ? "\(name.text)?" : name.text)
                        .font(theme.captionFont(size, strong: !trail)).italic(name.italic)
                        .lineLimit(now && !compact ? 2 : 1).minimumScaleFactor(0.75)
                        .contentTransition(.interpolate)
                    if trail && item.isNew {
                        Image(systemName: "sparkles").font(.system(size: 10 * scale)).foregroundStyle(.celebrate).accessibilityLabel("New for you")
                    }
                    if trail && saw {
                        Image(systemName: "eye.fill").font(.system(size: 10 * scale)).foregroundStyle(palette.accent).accessibilityLabel("You saw it")
                    }
                }
                if !trail { detail(saw: saw) }
                if expanded && !preview { actions(saw: saw).padding(.top, 6).transition(.opacity.combined(with: .offset(y: -6))) }
            }
        }
        .foregroundStyle(palette.ink)
        .opacity(opacity)
        .shadow(color: palette.background.opacity(preview ? 0 : 0.9), radius: 7)
        .shadow(color: palette.background.opacity(preview ? 0 : 0.7), radius: 1.5)
        .accessibilityElement(children: expanded ? .contain : .ignore)
        .accessibilityLabel("\(name.text), \(item.confidence.shownPercent) percent, \(now ? "calling now" : trail ? "heard earlier" : "maybe")")
        .accessibilityHint("Shows its actions")
        .accessibilityAddTraits(.isButton)
    }

    /// What a list row offers, as chips: I saw it, Not it, and the way to its page; a maybe gets Log it.
    @ViewBuilder private func actions(saw: Bool) -> some View {
        HStack(spacing: 7) {
            if let m = item.maybe {
                Button { act { listener.logMaybe(m, confirmed: false) } } label: { Label("Log it", systemImage: "plus") }
                    .buttonStyle(StageChip(palette: palette))
                Button { act { listener.logMaybe(m, confirmed: true) } } label: { Label("Saw it", systemImage: "eye") }
                    .buttonStyle(StageChip(palette: palette, tint: palette.accent))
            } else if let d = item.detection {
                Button { act { d.confirmed.toggle() } } label: { Label(saw ? "Saw it" : "I saw it", systemImage: saw ? "checkmark" : "eye") }
                    .buttonStyle(StageChip(palette: palette, tint: palette.accent))
            }
            Button(action: notIt) { Label("Not it", systemImage: "xmark") }
                .buttonStyle(StageChip(palette: palette))
            if let open {
                Button { act(open) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(StageChip(palette: palette)).accessibilityLabel("Open its page")
            }
        }
    }

    /// The small line under a name: how sure, and the other name.
    @ViewBuilder private func detail(saw: Bool) -> some View {
        let small = Font.system(size: (compact ? 11 : 12) * scale, weight: .semibold).monospacedDigit()
        HStack(spacing: 5) {
            switch item.kind {
            case .now:
                if item.agreed {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11 * scale)).foregroundStyle(palette.accent)
                        .accessibilityLabel("Both models agree")
                }
                Text("\(item.confidence.shownPercent)%").font(small)
                if saw {
                    Image(systemName: "eye.fill").font(.system(size: 11 * scale)).foregroundStyle(palette.accent).accessibilityLabel("You saw it")
                }
                if item.isNew {      // the moment itself: a first for your list
                    HStack(spacing: 3) { Image(systemName: "sparkles"); Text("New for you") }
                        .font(small).foregroundStyle(.celebrate).fixedSize()
                }
                if let other = NameBook.shared.secondary(item.label.common, item.label.scientific, species: item.label.group.isSpecies) {
                    Text(other.text).font(theme.captionFont((compact ? 12 : 13) * scale, strong: false)).italic(other.italic).opacity(0.8).lineLimit(1)
                }
            case .unusual:
                Text("\(item.reason) · \(item.confidence.shownPercent)%").font(small).foregroundStyle(.orange).lineLimit(1)
            default:
                Text("maybe · \(item.confidence.shownPercent)%").font(small).opacity(0.85)
            }
        }
    }
}

/// A group glyph on dark glass, as it's drawn over the spectrogram; a ring around it shows how sure the ID is.
struct StageDisc: View {
    let group: TaxonGroup
    var size: CGFloat = 36
    let palette: SpectrogramPalette
    /// Shown confidence, 0...1.
    var ring: Float?
    /// A badge symbol at the corner ("?" for a maybe, "!" for unusual here).
    var mark: String?
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            if theme.isPixel {
                TaxonIcon(group: group, size: size)
            } else {
                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, palette.scheme)
                Circle().fill(palette.background.opacity(0.3))
                Image(symbol: group.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(palette.ink)
                Circle().strokeBorder(palette.ink.opacity(0.3), lineWidth: 1)
                if let ring {
                    Circle().stroke(palette.ink.opacity(0.16), lineWidth: 2.5).padding(-5)
                    Circle().trim(from: 0, to: CGFloat(min(max(ring, 0.02), 1)))
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(-5)
                        .animation(.easeOut(duration: 0.4), value: ring)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let mark {
                Image(systemName: mark).font(.system(size: size * 0.42)).foregroundStyle(.white, mark.hasPrefix("exclam") ? Color.orange : Color.gray)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

private struct Haze: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { content.blur(radius: on ? 9 : 0).opacity(on ? 0 : 1) }
}

extension AnyTransition {
    /// Captions come out of a haze, drifting in from the edge, and leave by sinking into one.
    static var caption: AnyTransition {
        .asymmetric(insertion: .modifier(active: Haze(on: true), identity: Haze(on: false)).combined(with: .offset(x: -20)),
                    removal: .modifier(active: Haze(on: true), identity: Haze(on: false)).combined(with: .offset(y: 16)))
    }
}

/// A round button on dark glass, for the few controls that sit on the spectrogram itself.
struct GlassCircle: ButtonStyle {
    let palette: SpectrogramPalette
    var size: CGFloat = 38
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)).foregroundStyle(palette.ink)
            .frame(width: size, height: size)
            .background { Circle().fill(.ultraThinMaterial).environment(\.colorScheme, palette.scheme) }
            .overlay { Circle().strokeBorder(palette.ink.opacity(0.2), lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Circle().inset(by: -4))
    }
}
