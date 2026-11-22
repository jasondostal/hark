import Foundation
import CoreML
import HarkCore

/// BirdNET+ Geomodel V3.0.4 (Apache 2.0): (lat, lon, week) -> probability each of 14,082 species occurs there that
/// week. Tiny (15 MB, microseconds a run), so Hark runs all 48 weeks for a place to tell "wrong season" from
/// "never here". geo_map.bin maps each Perch label to its geomodel output (tools/convert_geomodel.py).
final class GeoModel: @unchecked Sendable {
    private let model: MLModel
    private let map: [UInt16]

    init?() {
        guard let url = Bundle.main.url(forResource: "Geo", withExtension: "mlmodelc"),
              let mapURL = Bundle.main.url(forResource: "geo_map", withExtension: "bin"),
              let data = try? Data(contentsOf: mapURL) else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuOnly
        guard let m = try? MLModel(contentsOf: url, configuration: cfg) else { return nil }
        model = m
        map = data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)).map { UInt16(littleEndian: $0) } }
    }

    var coveredLabels: Int { map.filter { $0 != 0xFFFF }.count }

    /// Sigmoid outputs for one place and week, in geomodel order.
    private func predict(_ lat: Double, _ lon: Double, week: Int) -> [Float]? {
        guard let input = try? MLMultiArray(shape: [1, 3], dataType: .float32) else { return nil }
        input[0] = NSNumber(value: Float(lat)); input[1] = NSNumber(value: Float(lon)); input[2] = NSNumber(value: Float(week))
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": input])),
              let logits = out.featureValue(for: "logits")?.multiArrayValue else { return nil }
        let n = logits.count
        var p = [Float](repeating: 0, count: n)
        let ptr = logits.dataPointer.bindMemory(to: Float.self, capacity: n)
        for k in 0..<n { p[k] = 1 / (1 + expf(-ptr[k])) }
        return p
    }

    /// This week's probability and the year's peak for every Perch label the geomodel knows.
    func expectations(latitude: Double, longitude: Double, week: Int) -> LocalContext.Geo? {
        var peak: [Float]?
        var now: [Float]?
        for w in 1...48 {
            guard let p = predict(latitude, longitude, week: w) else { return nil }
            if w == week { now = p }
            if peak == nil { peak = p } else { for k in p.indices where p[k] > peak![k] { peak![k] = p[k] } }
        }
        guard let now, let peak else { return nil }
        let wk = map.map { $0 == 0xFFFF ? nil : now[Int($0)] }
        let yr = map.map { $0 == 0xFFFF ? nil : peak[Int($0)] }
        return LocalContext.Geo(week: wk, yearMax: yr)
    }
}
