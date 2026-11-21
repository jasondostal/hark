import Foundation

/// What the widgets show, written by the app into the shared App Group container.
struct WidgetSnapshot: Codable {
    struct Item: Codable, Hashable { var name: String; var symbol: String; var time: Date; var isFirst: Bool }
    var lifeCount = 0
    var todayCount = 0
    var today: [Item] = []          // newest first, distinct species
    var listening = false
    var updated = Date.distantPast

    static let group = "group.dev.ducktyping.hark"
    /// false until the App Group entitlement is in the build (see project.yml); widgets then show only Listen.
    static var available: Bool { url != nil }
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appending(path: "widget.json")
    }
    static func load() -> WidgetSnapshot {
        guard let url, let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: d) else { return .init() }
        // a new day: yesterday's list no longer counts as "today"
        if !Calendar.current.isDateInToday(s.updated) { var t = s; t.today = []; t.todayCount = 0; return t }
        return s
    }
    func save() {
        guard let url = Self.url, let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: url, options: .atomic)
    }
}
