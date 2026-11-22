import AVFoundation
import Accelerate

/// Microphone -> 32 kHz mono Float32 chunks. Uses .measurement mode so iOS doesn't apply voice processing / AGC,
/// which would distort animal sounds.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 32_000, channels: 1, interleaved: false)!
    /// Called on the audio thread with converted samples and the chunk's RMS in dBFS.
    var onSamples: (([Float], Float) -> Void)?

    // Rumble filter: 2nd-order Butterworth high-pass on the 32 kHz stream (feeds both Perch and the spectrogram).
    private let filterLock = NSLock()
    private var wantHz: Double = 0, haveHz: Double = -1
    private var biquad: vDSP_biquad_Setup?
    private var delay = [Float](repeating: 0, count: 4)
    /// 0 = off. Takes effect on the next chunk.
    func setHighPass(_ hz: Double) { filterLock.lock(); wantHz = hz; filterLock.unlock() }

    private func highPass(_ x: inout [Float]) {
        filterLock.lock(); let hz = wantHz; filterLock.unlock()
        if hz != haveHz {
            if let b = biquad { vDSP_biquad_DestroySetup(b); biquad = nil }
            delay = [0, 0, 0, 0]; haveHz = hz
            if hz > 0 {
                let w0 = 2 * Double.pi * hz / 32_000, cs = cos(w0), alpha = sin(w0) / (2 * 0.70710678)
                let a0 = 1 + alpha
                let c = [(1 + cs) / 2 / a0, -(1 + cs) / a0, (1 + cs) / 2 / a0, -2 * cs / a0, (1 - alpha) / a0]
                biquad = vDSP_biquad_CreateSetup(c, 1)
            }
        }
        guard let b = biquad else { return }
        var y = [Float](repeating: 0, count: x.count)
        vDSP_biquad(b, &delay, x, 1, &y, 1, vDSP_Length(x.count))
        x = y
    }

    /// External mics (USB-C, wired). Built-in is "Automatic".
    static func inputs() -> [AVAudioSessionPortDescription] {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playAndRecord {
            try? s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        return s.availableInputs ?? []
    }
    var preferredInputUID: String?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord so selections and saved clips can play while listening; A2DP only, so Bluetooth headphones
        // never pull the mic over to a hands-free headset.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setPreferredSampleRate(48_000)
        let port = session.availableInputs?.first { $0.uid == preferredInputUID }
        try? session.setPreferredInput(port)       // nil = automatic
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { throw NSError(domain: "Hark", code: 2, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"]) }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
            self?.convert(buf)
        }
        engine.prepare()
        try engine.start()
    }

    /// Testing aid (`-feedfile a.wav,b.wav`): stream files in real time through the same convert path as the mic.
    private var feedTask: Task<Void, Never>?
    var onFilesDone: (() -> Void)?
    func startFiles(_ urls: [URL]) {
        feedTask = Task.detached { [weak self] in
            for url in urls {
                guard let f = try? AVAudioFile(forReading: url) else { NSLog("HARK feedfile: can't open \(url.path)"); continue }
                self?.converter = AVAudioConverter(from: f.processingFormat, to: self!.outFormat)
                let chunk: AVAudioFrameCount = 4096
                while !Task.isCancelled, let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: chunk) {
                    do { try f.read(into: buf, frameCount: chunk) } catch { break }
                    if buf.frameLength == 0 { break }
                    self?.convert(buf)
                    try? await Task.sleep(for: .seconds(Double(buf.frameLength) / f.processingFormat.sampleRate))
                }
            }
            NSLog("HARK feedfile: done")
            if !Task.isCancelled { self?.onFilesDone?() }
        }
    }

    func stop() {
        if let t = feedTask { t.cancel(); feedTask = nil; return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convert(_ buf: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, let ch = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let n = Int(out.frameLength)
        var samples = Array(UnsafeBufferPointer(start: ch, count: n))
        highPass(&samples)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(n))
        onSamples?(samples, 20 * log10(max(rms, 1e-7)))
    }
}
