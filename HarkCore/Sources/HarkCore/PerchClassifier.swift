import CoreML
import Foundation

/// Perch 2.0 (Core ML, fp16-safe frontend; see ~/working/perch-spike). Input: 5 s of 32 kHz mono, 160,000 floats.
public final class PerchClassifier: @unchecked Sendable {
    public static let sampleRate = 32_000
    public static let windowSamples = 160_000

    public struct Output: Sendable {
        public let logits: [Float]
        /// 500 frames x 128 mel bins, values = 0.1*log(mel) (about -1.15 floor). Row-major by frame.
        public let spectrogram: [Float]?
    }

    private let model: MLModel
    private let lock = NSLock()   // MLModel.prediction is thread-safe, but keep one in flight to bound memory.

    /// `url` is a compiled .mlmodelc (app bundle) or an .mlpackage (compiled on the fly; tests / Mac).
    public init(url: URL, computeUnits: MLComputeUnits = .all) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        var modelURL = url
        if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" {
            modelURL = try MLModel.compileModel(at: url)
        }
        model = try MLModel(contentsOf: modelURL, configuration: config)
    }

    public func classify(_ window: [Float]) throws -> Output {
        precondition(window.count == Self.windowSamples, "Perch needs exactly 160,000 samples")
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)], dataType: .float32)
        window.withUnsafeBufferPointer { src in
            let dst = input.dataPointer.bindMemory(to: Float.self, capacity: Self.windowSamples)
            dst.update(from: src.baseAddress!, count: Self.windowSamples)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: input)])
        lock.lock(); defer { lock.unlock() }
        let out = try model.prediction(from: provider)
        guard let l = out.featureValue(for: "logits")?.multiArrayValue else {
            throw NSError(domain: "Hark", code: 1, userInfo: [NSLocalizedDescriptionKey: "model has no logits output"])
        }
        return Output(logits: Self.floats(l), spectrogram: out.featureValue(for: "spectrogram")?.multiArrayValue.map(Self.floats))
    }

    static func floats(_ a: MLMultiArray) -> [Float] {
        let n = a.count
        switch a.dataType {
        case .float32:
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: n)
            return Array(UnsafeBufferPointer(start: p, count: n))
        case .float16:
            #if arch(arm64)
            let p = a.dataPointer.bindMemory(to: Float16.self, capacity: n)
            return UnsafeBufferPointer(start: p, count: n).map { Float($0) }
            #else
            return (0..<n).map { a[$0].floatValue }
            #endif
        default:
            return (0..<n).map { a[$0].floatValue }
        }
    }
}
