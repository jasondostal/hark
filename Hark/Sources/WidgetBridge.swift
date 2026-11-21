import Foundation
import SwiftData
import WidgetKit

/// Keeps the widget snapshot current: called after logging (debounced) and when listening starts/stops.
@MainActor
enum WidgetBridge {
    private static var pending: Task<Void, Never>?

    static func refresh(_ ctx: ModelContext?, listening: Bool, now: Bool = false) {
        pending?.cancel()
        pending = Task {
            if !now { try? await Task.sleep(for: .seconds(3)) }
            guard !Task.isCancelled, let ctx else { return }
            let start = Calendar.current.startOfDay(for: .now)
            let today = (try? ctx.fetch(FetchDescriptor<Detection>(predicate: #Predicate { $0.firstHeard >= start },
                                                                   sortBy: [SortDescriptor(\.firstHeard, order: .reverse)]))) ?? []
            var seen = Set<String>(), items: [WidgetSnapshot.Item] = []
            for d in today where seen.insert(d.scientific).inserted {
                items.append(.init(name: d.common, symbol: d.taxon.symbol, time: d.firstHeard, isFirst: d.isFirst))
            }
            var life = Set<String>()
            for d in (try? ctx.fetch(FetchDescriptor<Detection>())) ?? [] { life.insert(d.scientific) }
            WidgetSnapshot(lifeCount: life.count, todayCount: items.count, today: Array(items.prefix(6)),
                           listening: listening, updated: .now).save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
