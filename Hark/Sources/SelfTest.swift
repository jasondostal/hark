import Foundation
import HarkCore

/// `-selftest` launch argument: run Perch on bundled golden windows (TF reference top-1), print agreement + timing.
/// For on-device verification over `devicectl ... --console` without touching the UI.
/// The windows (selftest.f32/.json) are not in the repo: make them from your own audio with tools/models/perch
/// (make_fixtures.py). Without them the self-test logs that and exits.
enum SelfTest {
    struct Ref: Decodable { let species: String; let top1: Int }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let b = Bundle.main
                guard let refURL = b.url(forResource: "selftest", withExtension: "json"),
                      let rawURL = b.url(forResource: "selftest", withExtension: "f32") else {
                    NSLog("HARK-SELFTEST skipped: no selftest.f32/.json bundled (see tools/models/perch/README.md)")
                    return
                }
                let refs = try JSONDecoder().decode([Ref].self, from: Data(contentsOf: refURL))
                let raw = try Data(contentsOf: rawURL)
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
                    NSLog("HARK-SELFTEST \(unitName): load \(String(format: "%.1f", load)) s, top-1 \(agree)/\(refs.count), median \(String(format: "%.1f", ms[ms.count / 2])) ms/window")
                }
                if let url = BirdNET3Classifier.bundledURL,
                   let refURL = b.url(forResource: "birdnet3_selftest", withExtension: "json") {
                    struct BRef: Decodable { let top1: Int }
                    let brefs = try JSONDecoder().decode([BRef].self, from: Data(contentsOf: refURL))
                    let m = BirdNET3Classifier.windowSamples
                    for (unitName, units) in [("ANE", MLComputeUnitsBox.ane), ("GPU", .gpu), ("CPU", .cpu)] {
                        let t0 = Date()
                        let clf = try BirdNET3Classifier(url: url, computeUnits: units.value)
                        let load = Date().timeIntervalSince(t0)
                        _ = try clf.classify(Array(all[0..<m]))
                        var agree = 0; var ms: [Double] = []
                        for rep in 0..<3 {
                            for (i, r) in brefs.enumerated() {
                                let w = Array(all[(i * n)..<(i * n + m)])
                                let t = Date()
                                let out = try clf.classify(w)
                                ms.append(Date().timeIntervalSince(t) * 1000)
                                if rep == 0, let top = out.indices.max(by: { out[$0] < out[$1] }), top == r.top1 { agree += 1 }
                            }
                        }
                        ms.sort()
                        NSLog("HARK-SELFTEST BirdNET+ \(unitName): load \(String(format: "%.1f", load)) s, top-1 \(agree)/\(brefs.count), median \(String(format: "%.1f", ms[ms.count / 2])) ms/window")
                    }
                }
                NSLog("HARK-SELFTEST done")
            } catch { NSLog("HARK-SELFTEST error: \(error)") }
        }
    }
}

import CoreML
enum MLComputeUnitsBox {
    case ane, gpu, cpu
    var value: MLComputeUnits { switch self { case .ane: .cpuAndNeuralEngine; case .gpu: .cpuAndGPU; case .cpu: .cpuOnly } }
}
