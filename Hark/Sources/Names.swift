import SwiftUI
import HarkCore

/// Which name leads (Settings > Look > Names), and nicknames people give species ("Fred" for the yard cardinal).
@Observable final class NameBook {
    static let shared = NameBook()

    enum Style: String, CaseIterable, Identifiable {
        case common, scientific, both
        var id: String { rawValue }
        var title: String { switch self { case .common: "Common"; case .scientific: "Scientific"; case .both: "Both" } }
    }

    var style: Style = Style(rawValue: UserDefaults.standard.string(forKey: "names") ?? "") ?? .common {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "names") }
    }
    private(set) var nicknames: [String: String] = UserDefaults.standard.dictionary(forKey: "nicknames") as? [String: String] ?? [:]

    func nickname(_ scientific: String) -> String? { nicknames[scientific] }
    func setNickname(_ name: String, for scientific: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nicknames[scientific] = n.isEmpty ? nil : n
        UserDefaults.standard.set(nicknames, forKey: "nicknames")
    }

    struct Name { let text: String; let italic: Bool }

    /// The name a species goes by everywhere: its nickname, else the common or scientific name per `style`.
    /// Sounds ("Car", "Dog") only have the one name.
    func primary(_ common: String, _ scientific: String, species: Bool = true) -> Name {
        guard species else { return Name(text: common, italic: false) }
        if let n = nicknames[scientific] { return Name(text: n, italic: false) }
        return style == .scientific ? Name(text: scientific, italic: true) : Name(text: common, italic: false)
    }
    /// The other name, for the line under it on detail pages: the scientific name under a common name or nickname,
    /// the common name under a scientific one.
    func secondary(_ common: String, _ scientific: String, species: Bool = true) -> Name? {
        guard species else { return nil }
        if nicknames[scientific] != nil { return style == .scientific ? Name(text: scientific, italic: true) : Name(text: common, italic: false) }
        return style == .scientific ? Name(text: common, italic: false) : Name(text: scientific, italic: true)
    }
    /// In compact rows the other name only shows with "Both" (or under a nickname).
    func rowSecondary(_ common: String, _ scientific: String, species: Bool = true) -> Name? {
        guard species, style == .both || nicknames[scientific] != nil else { return nil }
        return secondary(common, scientific, species: species)
    }
    /// Plain text for titles, pins and sharing.
    func plain(_ common: String, _ scientific: String, species: Bool = true) -> String { primary(common, scientific, species: species).text }
}

/// A species' leading name in the look's name face, italic when it's scientific.
struct SpeciesTitle: View {
    let common: String
    let scientific: String
    var species = true
    var style: Font.TextStyle = .body
    var body: some View {
        let n = NameBook.shared.primary(common, scientific, species: species)
        Text(n.text).speciesName(style).italic(n.italic)
    }
}

/// The other name, small and secondary. `row`: only when the setting asks for it in lists.
struct SpeciesSubtitle: View {
    let common: String
    let scientific: String
    var species = true
    var row = false
    var font: Font = .caption
    var body: some View {
        let b = NameBook.shared
        if let n = row ? b.rowSecondary(common, scientific, species: species) : b.secondary(common, scientific, species: species) {
            Text(n.text).font(font).italic(n.italic).foregroundStyle(.secondary)
        }
    }
}

extension HarkCore.Label {
    var displayName: String { NameBook.shared.plain(common, scientific, species: group.isSpecies) }
}
extension Detection {
    var isSpecies: Bool { taxon.isSpecies }
    var displayName: String { NameBook.shared.plain(common, scientific, species: isSpecies) }
}

// MARK: Learn more

/// Where to read and hear more about a species.
enum SpeciesLinks {
    struct Link: Identifiable { let title: String; let symbol: String; let url: URL; var id: String { title } }

    static func links(scientific: String, common: String, group: TaxonGroup) -> [Link] {
        guard group.isSpecies else { return [] }
        let label = HarkCore.Label.table?.label(scientific: scientific)
        let sci = scientific.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? scientific
        let q = scientific.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scientific
        var out: [Link] = []
        func add(_ t: String, _ s: String, _ u: String) { if let url = URL(string: u) { out.append(Link(title: t, symbol: s, url: url)) } }
        if let code = label?.ebird {
            add("eBird", "binoculars", "https://ebird.org/species/\(code)")
            add("Recordings at the Macaulay Library", "waveform", "https://media.ebird.org/catalog?taxonCode=\(code)&mediaType=audio&sort=rating_rank_desc")
        }
        if group == .bird || group == .amphibian || group == .insect || group == .mammal {
            add("Recordings on xeno-canto", "music.note.list", "https://xeno-canto.org/species/" + scientific.replacingOccurrences(of: " ", with: "-"))
        }
        if let id = label?.inat { add("iNaturalist", "leaf", "https://www.inaturalist.org/taxa/\(id)") }
        else { add("iNaturalist", "leaf", "https://www.inaturalist.org/search?q=\(q)") }
        add("Wikipedia", "book", "https://en.wikipedia.org/wiki/\(sci.replacingOccurrences(of: "%20", with: "_"))")
        return out
    }
}

/// A "Learn more" section of links.
struct LearnMoreSection: View {
    let scientific: String
    let common: String
    let group: TaxonGroup
    var body: some View {
        let links = SpeciesLinks.links(scientific: scientific, common: common, group: group)
        if !links.isEmpty {
            Section {
                ForEach(links) { l in
                    Link(destination: l.url) {
                        LabeledContent { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary) } label: {
                            Label(l.title, systemImage: l.symbol)
                        }
                    }
                }
            } header: { Text("Learn more").themedHeader() }
        }
    }
}

/// Species page: give it a name of your own.
struct NicknameRow: View {
    let scientific: String
    @State private var text = ""
    var body: some View {
        TextField("Nickname (shows instead of its name)", text: $text)
            .submitLabel(.done)
            .onAppear { text = NameBook.shared.nickname(scientific) ?? "" }
            .onSubmit { NameBook.shared.setNickname(text, for: scientific) }
            .onDisappear { NameBook.shared.setNickname(text, for: scientific) }
    }
}
