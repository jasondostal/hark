import Foundation
import HarkCore

/// `-selftest` launch argument: run Perch on bundled golden windows (TF reference top-1), print agreement + timing.
/// For on-device verification over `devicectl ... --console` without touching the UI.
enum SelfTest {
    struct Ref: Decodable { let species: String; let top1: Int }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let b = Bundle.main
                let refs = try JSONDecoder().decode([Ref].self, from: Data(contentsOf: b.url(forResource: "selftest", withExtension: "json")!))
                let raw = try Data(contentsOf: b.url(forResource: "selftest", withExtension: "f32")!)
                let all = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let n = PerchClassifier.windowSamples
                for (unitName, units) in [("ANE", MLComputeUnitsBox.ane), ("GPU", .gpu), ("CPU", .cpu)] {
                    let t0 = Date()
                    let clf = try PerchClassifier(url: b.url(forResource: "Perch", withExtension: "mlmodelc")!, computeUnits: units.value)
                    let load = Date().timeIntervalSince(t0)
                    _ = try clf.classify(Array(all[0..<n]))
                    var agree = 0; var ms: [Double] = []
                    for rep in 0..<3 {
                        for (i, r) in refs.enumerated() {
                            let t = Date()
                            let out = try clf.classify(Array(all[(i * n)..<((i + 1) * n)]))
                            ms.append(Date().timeIntervalSince(t) * 1000)
                            if rep == 0 && Scoring.topK(out.logits, 1)[0] == r.top1 { agree += 1 }
                        }
                    }
                    ms.sort()
                    print("HARK-SELFTEST \(unitName): load \(String(format: "%.1f", load)) s, top-1 \(agree)/\(refs.count), median \(String(format: "%.1f", ms[ms.count / 2])) ms/window")
                }
                print("HARK-SELFTEST done")
            } catch { print("HARK-SELFTEST error: \(error)") }
        }
    }
}

import CoreML
enum MLComputeUnitsBox {
    case ane, gpu, cpu
    var value: MLComputeUnits { switch self { case .ane: .cpuAndNeuralEngine; case .gpu: .cpuAndGPU; case .cpu: .cpuOnly } }
}
