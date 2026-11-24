import SwiftUI
import UIKit
import MapKit
import CoreLocation
import HarkCore

/// A picture of a detection to send with its recording: the call's spectrogram with its critter pin, the name, when,
/// how sure, and (only if asked for, every time) where. Drawn in the current look.
struct ShareCardModel {
    enum Place: String, CaseIterable, Identifiable {
        case none, town, map
        var id: String { rawValue }
        var title: String { switch self { case .none: "None"; case .town: "Town"; case .map: "Map" } }
    }

    let name: NameBook.Name
    let other: NameBook.Name?
    let group: TaxonGroup
    let when: Date
    let percent: Int
    let confirmed: Bool
    var spectrogram: CGImage?
    /// Where the call is loudest, as fractions of the spectrogram (x from the left, y from the top).
    var peak: CGPoint?
    var town: String?
    var map: UIImage?

    @MainActor init(_ d: Detection) {
        let b = NameBook.shared
        name = b.primary(d.common, d.scientific, species: d.isSpecies)
        other = b.secondary(d.common, d.scientific, species: d.isSpecies)
        group = d.taxon; when = d.firstHeard; percent = d.confidence.shownPercent; confirmed = d.confirmed
    }

    /// The clip's spectrogram and its loudest spot (bands 12+, as the live pins do).
    static func spectrogram(file: String) async -> (CGImage, CGPoint)? {
        await Task.detached(priority: .userInitiated) { () -> (CGImage, CGPoint)? in
            guard let s = ClipStore.load(file) else { return nil }
            let lv = SpectrogramDSP.levels(of: s)
            let h = SpectrogramDSP.bins
            // Crop silent columns off the ends (a clip can start before the mic had anything).
            let loud = (0..<lv.columns).filter { c in (0..<h).contains { lv.data[c * h + $0] > 0 } }
            guard let first = loud.first, let last = loud.last,
                  let img = SpectrogramDSP.image(lv.data, columns: lv.columns, range: first..<(last + 1)) else { return nil }
            var best = (score: -1, c: first, b: 0)
            for c in first...last {
                let base = c * h
                for b in 13..<(h - 1) where SpectrogramDSP.bandHz(b) < 11_000 {
                    let v = Int(lv.data[base + b - 1]) + 2 * Int(lv.data[base + b]) + Int(lv.data[base + b + 1])
                    if v > best.score { best = (v, c, b) }
                }
            }
            return (img, CGPoint(x: (CGFloat(best.c - first) + 0.5) / CGFloat(last + 1 - first), y: 1 - CGFloat(best.b) / CGFloat(h)))
        }.value
    }

    /// "Madison, WI": the nearest town, not the spot.
    static func town(_ c: CLLocationCoordinate2D) async -> String? {
        let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        guard let p else { return nil }
        return [p.locality ?? p.subAdministrativeArea, p.administrativeArea].compactMap { $0 }.joined(separator: ", ")
    }

    /// A small map with the exact spot in the middle.
    static func map(_ c: CLLocationCoordinate2D, dark: Bool) async -> UIImage? {
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: c, latitudinalMeters: 1600, longitudinalMeters: 3200)
        o.size = CGSize(width: 330, height: 120)
        o.scale = 3
        o.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return try? await MKMapSnapshotter(options: o).start().image
    }
}

/// The card itself, 360 x 450 points (4:5; taller with a map), rendered at 3x.
struct ShareCardView: View {
    let model: ShareCardModel
    let theme: AppTheme
    let palette: SpectrogramPalette

    private var bg: Color { theme.background ?? Color(hex: 0xF2F2F7) }
    private var card: Color { theme.card ?? .white }
    private var ink: Color { theme.ink ?? Color(hex: 0x111111) }
    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            spectrogram
            HStack(alignment: .center, spacing: 12) {
                TaxonIcon(group: model.group, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name.text).font(theme.nameFont(.title2)).italic(model.name.italic)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    if let o = model.other {
                        Text(o.text).font(.subheadline).italic(o.italic).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                chip("\(model.percent)%", symbol: "waveform", color: accent)
                if model.confirmed { chip("Seen", symbol: "checkmark.seal.fill", color: theme.good) }
                Spacer(minLength: 0)
            }
            Label(model.when.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()), systemImage: "clock")
                .font(.subheadline).foregroundStyle(ink.opacity(0.75))
            if let map = model.map {
                Image(uiImage: map).resizable().scaledToFill()
                    .frame(height: 76).frame(maxWidth: .infinity).clipped()
                    .overlay { Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.white, .red).shadow(radius: 2) }
                    .clipShape(RoundedRectangle(cornerRadius: theme.isPixel ? 0 : 10))
            }
            if let town = model.town {
                Label(town, systemImage: "location.fill").font(.subheadline).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "ear.badge.waveform").font(.caption.weight(.semibold))
                Text("Heard with Hark").font(theme.headerFont(.caption) ?? .caption.weight(.semibold))
                Spacer()
                Text("identified on iPhone").font(.caption2)
            }
            .foregroundStyle(ink.opacity(0.55))
        }
        .padding(18)
        .frame(width: 360, height: model.map == nil ? 450 : 520, alignment: .top)
        .background(bg)
        .foregroundStyle(ink)
        .environment(\.theme, theme)
        .environment(\.colorScheme, theme.scheme ?? .light)
        .fontDesign(theme.fontDesign)
    }

    private var spectrogram: some View {
        ZStack {
            palette.background
            if let img = model.spectrogram {
                Image(decorative: img, scale: 1).resizable().interpolation(palette.isPixel ? .none : .medium)
            }
            FrequencyAxis(color: palette.labelColor, pixel: palette.isPixel)
            if let p = model.peak {
                GeometryReader { g in
                    CritterMarker(group: model.group, pixel: palette.isPixel)
                        .position(x: min(max(p.x * g.size.width, 20), g.size.width - 20), y: max(p.y * g.size.height - 20, 14))
                }
            }
        }
        .frame(height: model.map == nil ? 190 : 170)
        .clipShape(RoundedRectangle(cornerRadius: theme.isPixel ? 0 : 14))
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Capsule()))
    }

    @MainActor func render() -> UIImage? {
        let r = ImageRenderer(content: self)
        r.scale = 3
        return r.uiImage
    }
}

/// Detection page > Share: preview the card, choose what goes with it, then the share sheet.
struct ShareCardSheet: View {
    let detection: Detection
    @Environment(\.theme) private var theme
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    /// Location is never shared unless picked here, each time.
    @State private var place: ShareCardModel.Place = {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments   // screenshot aid: -shareplace map
        if let i = a.firstIndex(of: "-shareplace"), i + 1 < a.count, let p = ShareCardModel.Place(rawValue: a[i + 1]) { return p }
        #endif
        return .none
    }()
    @State private var withClip = true
    @State private var model: ShareCardModel?
    @State private var image: UIImage?

    private var coordinate: CLLocationCoordinate2D? {
        guard let la = detection.latitude, let lo = detection.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
    private var hasClip: Bool { detection.clipFile.map { FileManager.default.fileExists(atPath: ClipStore.url($0).path) } ?? false }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().frame(height: 300) }
                    }
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                    .accessibilityLabel("Preview of the card")
                }
                Section {
                    Picker("Location", selection: $place) {
                        ForEach(ShareCardModel.Place.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(coordinate == nil)
                    if hasClip { Toggle("Include the recording", isOn: $withClip) }
                } footer: {
                    Text(coordinate == nil ? "This detection has no location." :
                         "Location stays off unless you pick it. Town adds the nearest town; Map adds a small map of the exact spot. What you see above is exactly what gets sent.")
                }
            }.themedRows() }.themedList()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Share") { share() }.disabled(image == nil) }
            }
            .task { await build() }
            .onChange(of: place) { Task { await build() } }
        }
    }

    private func build() async {
        var m = model ?? ShareCardModel(detection)
        if m.spectrogram == nil, let f = detection.clipFile, let (img, peak) = await ShareCardModel.spectrogram(file: f) {
            m.spectrogram = img; m.peak = peak
        }
        m.town = nil; m.map = nil
        if let c = coordinate {
            if place == .town || place == .map { m.town = await ShareCardModel.town(c) }
            if place == .map { m.map = await ShareCardModel.map(c, dark: theme.scheme == .dark) }
        }
        model = m
        image = ShareCardView(model: m, theme: theme, palette: listener.palette).render()
    }

    private var message: String {
        let d = detection
        let sci = d.isSpecies && d.displayName != d.scientific ? " (\(d.scientific))" : ""
        let when = d.firstHeard.formatted(date: .abbreviated, time: .shortened)
        let whereText = place != .none ? (model?.town).map { " near \($0)" } ?? "" : ""
        return "Heard a \(d.displayName)\(sci)\(whereText) on \(when), \(d.confidence.shownPercent)% sure\(d.confirmed ? ", and saw it" : ""). Identified on my iPhone with Hark."
    }

    private func share() {
        guard let image else { return }
        var items: [Any] = [message]
        if let png = image.pngData(), let url = try? writeExport(png, name: "\(detection.displayName) - Hark.png") { items.append(url) }
        if withClip, hasClip, let f = detection.clipFile, let url = try? copyClipForSharing(f, title: clipTitle) { items.append(url) }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topViewController()?.present(vc, animated: true)
    }

    private var clipTitle: String {
        let d = detection.firstHeard
        return "\(detection.displayName) \(d.formatted(.iso8601.year().month().day())) \(d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))"
    }
}

private func writeExport(_ data: Data, name: String) throws -> URL {
    let dir = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: name.replacingOccurrences(of: "/", with: "-"))
    try data.write(to: url)
    return url
}

func copyClipForSharing(_ file: String, title: String) throws -> URL {
    let dir = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dst = dir.appending(path: title.replacingOccurrences(of: "/", with: "-") + ".m4a")
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.copyItem(at: ClipStore.url(file), to: dst)
    return dst
}

@MainActor private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    var vc = scene?.keyWindow?.rootViewController
    while let p = vc?.presentedViewController { vc = p }
    return vc
}
