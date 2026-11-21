import Foundation
import AVFoundation
import Observation

/// Saved audio for logged detections: AAC .m4a, 32 kHz mono (~6 KB/s) in Application Support/Clips.
enum ClipStore {
    static let sampleRate = 32_000.0

    static var directory: URL {
        let d = URL.applicationSupportDirectory.appending(path: "Clips", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ name: String) -> URL { directory.appending(path: name) }

    /// Encode off the main thread. Returns the file name to store on the Detection.
    static func save(_ samples: [Float], name: String = UUID().uuidString + ".m4a") async -> String? {
        await Task.detached(priority: .utility) {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                                           AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
            guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            do {
                let f = try AVAudioFile(forWriting: url(name), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try f.write(from: buf)
                return name
            } catch { NSLog("HARK clip save failed: \(error)"); return nil }
        }.value
    }

    /// Decode a saved clip back to 32 kHz mono floats (for its spectrogram).
    static func load(_ name: String) -> [Float]? {
        guard let f = try? AVAudioFile(forReading: url(name), commonFormat: .pcmFormatFloat32, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil, let ch = buf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(name))
    }
}

/// Plays a selection or a saved clip through the speaker. While it plays, Listener ignores the mic so Hark
/// doesn't identify its own playback.
@MainActor
@Observable
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = ClipPlayer()
    private(set) var playingID: String?
    private var player: AVAudioPlayer?
    /// Called with the playback duration so the listener can mute itself.
    var onPlay: ((TimeInterval) -> Void)?

    func toggle(id: String, samples: @autoclosure () -> [Float]?, file: URL? = nil) {
        if playingID == id { stop(); return }
        stop()
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord { try? session.setCategory(.playback); try? session.setActive(true) }
        do {
            if let file { player = try AVAudioPlayer(contentsOf: file) }
            else if let s = samples() { player = try AVAudioPlayer(data: Self.wav(s)) }
            else { return }
        } catch { NSLog("HARK playback failed: \(error)"); return }
        player?.delegate = self
        player?.play()
        playingID = id
        onPlay?(player?.duration ?? 0)
    }

    func stop() { player?.stop(); player = nil; playingID = nil }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) {
        Task { @MainActor in self.playingID = nil; self.player = nil }
    }

    /// 16-bit PCM WAV in memory, normalized so quiet field audio is audible.
    static func wav(_ s: [Float]) -> Data {
        let peak = max(s.map(abs).max() ?? 0, 1e-4)
        let gain = min(0.9 / peak, 30)
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = s.count * 2, sr = UInt32(ClipStore.sampleRate)
        d.append(contentsOf: "RIFF".utf8); put(UInt32(36 + bytes)); d.append(contentsOf: "WAVEfmt ".utf8)
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(sr); put(sr * 2); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: "data".utf8); put(UInt32(bytes))
        d.reserveCapacity(d.count + bytes)
        for x in s { put(Int16(max(-1, min(1, x * gain)) * 32767)) }
        return d
    }
}
