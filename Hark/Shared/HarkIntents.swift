import AppIntents
import ActivityKit

/// "Start Listening": Action Button, Control Center, Lock Screen, Shortcuts, Siri. Opens Hark already listening
/// (if the model is still loading on a cold launch, listening starts the moment it's ready).
struct StartListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Listening"
    static let description = IntentDescription("Open Hark and start identifying what you hear.")
    static let openAppWhenRun = true

    #if HARK_APP
    @MainActor func perform() async throws -> some IntentResult {
        await Listener.shared.requestStart()
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult { .result() }
    #endif
}

/// Stop button on the Live Activity. LiveActivityIntent runs in the app's process without opening it.
struct StopListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Listening"
    static let description = IntentDescription("Stop Hark listening.")

    #if HARK_APP
    @MainActor func perform() async throws -> some IntentResult {
        Listener.shared.stop()
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult { .result() }
    #endif
}

/// Lock Screen / Dynamic Island while listening.
struct ListeningAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var species: Int            // distinct species this session
        var latest: String?         // most recent new species
        var latestSymbol: String?
        var latestIsFirst: Bool     // first time ever ("New for you")
        var finished = false        // a point count that ran its time: the card stays a while with the tally
    }
    var started: Date
    var title = "Hark is listening" // "Point count", "Survey"
    var endsAt: Date?               // point count: when it stops
}
