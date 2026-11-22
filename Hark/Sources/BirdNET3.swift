import Foundation
import CoreML

/// BirdNET+ V3.0 Global 12K (Apache 2.0): 3 s of 32 kHz mono in, 11,725 sigmoid scores out (11,709 animals, 16 sounds).
/// Converted by tools/convert_birdnet3.py. Labels in birdnet3_labels.json, output order.
final class BirdNET3Classifier: @unchecked Sendable {
    static let windowSamples = 96_000
    private let model: MLModel

    init(url: URL, computeUnits: MLComputeUnits) throws {
        let cfg = MLModelConfiguration(); cfg.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: cfg)
    }

    static var bundledURL: URL? { Bundle.main.url(forResource: "BirdNET3", withExtension: "mlmodelc") }

    func classify(_ window: [Float]) throws -> [Float] {
        precondition(window.count == Self.windowSamples, "BirdNET+ needs exactly 96,000 samples")
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)], dataType: .float32)
        window.withUnsafeBufferPointer { src in
            input.dataPointer.bindMemory(to: Float.self, capacity: Self.windowSamples).update(from: src.baseAddress!, count: Self.windowSamples)
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": input]))
        guard let s = out.featureValue(for: "predictions")?.multiArrayValue else { return [] }
        let n = s.count
        var r = [Float](repeating: 0, count: n)
        if s.dataType == .float16 {
            let p = s.dataPointer.bindMemory(to: Float16.self, capacity: n)
            for i in 0..<n { r[i] = Float(p[i]) }
        } else {
            let p = s.dataPointer.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { r[i] = p[i] }
        }
        return r
    }
}
