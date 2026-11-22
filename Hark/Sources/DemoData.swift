#if DEBUG
import Foundation
import SwiftData
import AVFoundation
import HarkCore

/// Screenshot aid (`-demolog <dir of species wavs>`, Debug builds only): replaces the log with three made-up listening
/// sessions at Horicon Marsh, Wisconsin, with clips cut from the recordings in <dir> (named Genus_species_*.wav).
@MainActor
enum DemoData {
    static func seedIfRequested(_ ctx: ModelContext) async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demolog"), i + 1 < args.count, let table = HarkCore.Label.table else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? ctx.delete(model: Detection.self); try? ctx.delete(model: ListeningSession.self)

        let day: TimeInterval = 86_400
        let now = Date()
        func at(_ daysAgo: Double, _ hour: Int, _ minute: Int) -> Date {
            let d = Calendar.current.startOfDay(for: now.addingTimeInterval(-daysAgo * day))
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
        }
        // (scientific, minutes into the session, minutes heard, confidence, confirmed, first)
        typealias Row = (String, Double, Double, Double, Bool, Bool)
        let sessions: [(start: Date, minutes: Double, route: [(Double, Double)], rows: [Row])] = [
            (at(2, 6, 12), 74, [(43.4588, -88.6315), (43.4601, -88.6302), (43.4622, -88.6290), (43.4645, -88.6283),
                                (43.4668, -88.6271), (43.4690, -88.6262), (43.4712, -88.6250), (43.4733, -88.6236)], [
                ("Branta canadensis", 2, 9, 0.93, true, false), ("Anas platyrhynchos", 6, 4, 0.71, false, false),
                ("Aix sponsa", 14, 2, 0.58, true, true), ("Megaceryle alcyon", 22, 1, 0.66, false, false),
                ("Turdus migratorius", 27, 6, 0.81, false, false), ("Corvus brachyrhynchos", 35, 3, 0.88, false, false),
                ("Dumetella carolinensis", 41, 5, 0.62, true, false), ("Zonotrichia albicollis", 50, 2, 0.74, false, false),
                ("Meleagris gallopavo", 61, 1, 0.55, false, false)]),
            (at(1, 20, 34), 41, [(43.4561, -88.6342), (43.4563, -88.6339)], [
                ("Pseudacris crucifer", 0, 38, 0.97, false, false), ("Strix varia", 9, 3, 0.86, true, true),
                ("Bubo virginianus", 18, 2, 0.79, false, false), ("Megascops asio", 26, 1, 0.61, false, true),
                ("Oecanthus fultoni", 30, 9, 0.68, false, false)]),
            (at(0, 7, 3), 38, [(43.4561, -88.6342), (43.4566, -88.6333), (43.4572, -88.6327), (43.4580, -88.6321)], [
                ("Cardinalis cardinalis", 1, 14, 0.91, true, false), ("Poecile atricapillus", 3, 22, 0.94, true, false),
                ("Cyanocitta cristata", 8, 6, 0.89, false, false), ("Sitta carolinensis", 12, 3, 0.77, false, false),
                ("Spinus tristis", 17, 4, 0.72, false, false), ("Zenaida macroura", 21, 5, 0.84, false, false),
                ("Dryocopus pileatus", 26, 1, 0.69, true, true), ("Tamias striatus", 31, 2, 0.57, false, false),
                ("Turdus migratorius", 33, 4, 0.83, false, false)]),
        ]
        for s in sessions {
            let id = UUID()
            let rec = ListeningSession(id: id, started: s.start)
            rec.ended = s.start.addingTimeInterval(s.minutes * 60)
            rec.trackLat = s.route.map(\.0); rec.trackLon = s.route.map(\.1)
            ctx.insert(rec)
            for (k, r) in s.rows.enumerated() {
                guard let li = table.index(ofScientific: r.0) else { continue }
                let p = s.route[min(k * s.route.count / max(s.rows.count, 1), s.route.count - 1)]
                let d = Detection(label: table[li], confidence: r.3, at: s.start.addingTimeInterval(r.1 * 60), windows: Int(r.2 * 12),
                                  latitude: p.0, longitude: p.1, sessionID: id, source: "live")
                d.lastHeard = d.firstHeard.addingTimeInterval(r.2 * 60)
                d.confirmed = r.4; d.isFirst = r.5
                ctx.insert(d)
                if let samples = clip(for: r.0, in: dir) { d.clipFile = await ClipStore.save(samples) }
            }
        }
        try? ctx.save()
    }

    /// The loudest 5 s of the first recording of a species, as 32 kHz mono.
    private static func clip(for scientific: String, in dir: URL) -> [Float]? {
        let prefix = scientific.replacingOccurrences(of: " ", with: "_")
        guard let name = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.sorted().first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(".wav") }),
              let file = try? AVAudioFile(forReading: dir.appending(path: name)),
              let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 32_000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: file.processingFormat, to: out),
              let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: src)) != nil,
              let dst = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(Double(file.length) * 32_000 / file.processingFormat.sampleRate) + 1024)
        else { return nil }
        var fed = false
        conv.convert(to: dst, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return src
        }
        guard let ch = dst.floatChannelData?[0] else { return nil }
        let all = Array(UnsafeBufferPointer(start: ch, count: Int(dst.frameLength)))
        let n = 5 * 32_000
        guard all.count > n else { return all }
        var best = 0, bestE: Float = -1
        for st in stride(from: 0, through: all.count - n, by: 16_000) {
            let e = all[st..<(st + n)].reduce(0) { $0 + $1 * $1 }
            if e > bestE { bestE = e; best = st }
        }
        return Array(all[best..<(best + n)])
    }
}
#endif
