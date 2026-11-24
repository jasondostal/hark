import Foundation
import SwiftData
import HarkCore

/// One logged occurrence: a species heard (continuously, gaps < 60 s) during a listening session.
@Model
final class Detection {
    var id: UUID
    var scientific: String
    var common: String
    var group: String
    var confidence: Double          // best softmax confidence seen
    var firstHeard: Date
    var lastHeard: Date
    var windows: Int                // 5 s windows it was heard in
    var latitude: Double?
    var longitude: Double?
    var confirmed: Bool             // "I saw it": the person verified the ID
    var sessionID: UUID
    var source: String              // "live", "file" (found in an imported recording), or logged by hand: "maybe" (under the threshold) / "unusual" (out of range) / "selection" (picked out on the spectrogram; "rewind" in older logs)
    var clipFile: String?           // saved audio in ClipStore.directory
    var isFirst: Bool = false       // the first time this species ever entered the log

    init(id: UUID = UUID(), label: HarkCore.Label, confidence: Double, at: Date, windows: Int = 1,
         latitude: Double?, longitude: Double?, sessionID: UUID, source: String) {
        self.id = id
        scientific = label.scientific; common = label.common; group = label.group.rawValue
        self.confidence = confidence; firstHeard = at; lastHeard = at; self.windows = windows
        self.latitude = latitude; self.longitude = longitude
        confirmed = false; self.sessionID = sessionID; self.source = source
    }

    var taxon: TaxonGroup { TaxonGroup(rawValue: group) ?? .unknown }
}

/// One press of Listen: when, how long, and the route walked (sampled about every 30 s while moving).
@Model
final class ListeningSession {
    var id: UUID
    var started: Date
    var ended: Date
    var trackLat: [Double] = []
    var trackLon: [Double] = []
    // 1.1 (all defaulted, so 1.0 stores open as they are)
    var kind: String = "live"       // "live", "point" (point count), "survey", "file" (an imported recording)
    var plannedSeconds: Int = 0     // point count length
    var title: String = ""          // your name for it; a file session starts with the file's name
    var note: String = ""
    var latitude: Double?           // where it started (a point count's station)
    var longitude: Double?

    init(id: UUID, started: Date) { self.id = id; self.started = started; ended = started }
}
