import ActivityKit
import UIKit

/// The Lock Screen / Dynamic Island card while listening. New species update it; while Hark is in the
/// background, a new species also lights the screen and buzzes (the Live Activity alert), so walk mode works
/// with the phone in a pocket.
@MainActor
final class LiveActivityController {
    private var activity: Activity<ListeningAttributes>?
    private var state = ListeningAttributes.ContentState(species: 0, latest: nil, latestSymbol: nil, latestIsFirst: false)

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        state = .init(species: 0, latest: nil, latestSymbol: nil, latestIsFirst: false)
        activity = try? Activity.request(attributes: ListeningAttributes(started: .now),
                                         content: .init(state: state, staleDate: nil))
    }

    func newSpecies(_ name: String, symbol: String, count: Int, firstEver: Bool) {
        guard let activity else { return }
        state = .init(species: count, latest: name, latestSymbol: symbol, latestIsFirst: firstEver)
        let background = UIApplication.shared.applicationState != .active
        let alert = background ? AlertConfiguration(title: firstEver ? "New for you!" : "Hark heard",
                                                    body: "\(name)", sound: .default) : nil
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content, alertConfiguration: alert) }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
