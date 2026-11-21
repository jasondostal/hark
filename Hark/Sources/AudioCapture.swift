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

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
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
        let samples = Array(UnsafeBufferPointer(start: ch, count: n))
        var rms: Float = 0
        vDSP_rmsqv(ch, 1, &rms, vDSP_Length(n))
        onSamples?(samples, 20 * log10(max(rms, 1e-7)))
    }
}
