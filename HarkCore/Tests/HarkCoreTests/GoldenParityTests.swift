import XCTest
import CoreML
@testable import HarkCore

/// The app's Core ML path must pick the same species as Google's TF Perch on real backyard audio.
/// Golden windows + reference top-1/top-5 come from ~/working/perch-spike (golden.npz, TF perch_v2_cpu).
/// Model: $HARK_MODEL or ../Models/Perch.mlpackage (git-ignored; copy from perch-spike/models).
final class GoldenParityTests: XCTestCase {
    struct Ref: Decodable { let species: String; let top1: Int; let top5: [Int]; let top1_logit: Float }

    static var modelURL: URL {
        if let p = ProcessInfo.processInfo.environment["HARK_MODEL"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Models/Perch.mlpackage")
    }

    func fixtures() throws -> (windows: [[Float]], refs: [Ref], labels: LabelTable) {
        let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        let refs = try JSONDecoder().decode([Ref].self, from: Data(contentsOf: dir.appendingPathComponent("golden.json")))
        let raw = try Data(contentsOf: dir.appendingPathComponent("golden_windows.f32"))
        let all = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let n = PerchClassifier.windowSamples
        XCTAssertEqual(all.count, refs.count * n)
        let windows = (0..<refs.count).map { Array(all[($0 * n)..<(($0 + 1) * n)]) }
        return (windows, refs, try LabelTable(contentsOf: dir.appendingPathComponent("labels.json")))
    }

    func run(_ units: MLComputeUnits, name: String) throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else {
            throw XCTSkip("model not found at \(Self.modelURL.path)")
        }
        let (windows, refs, labels) = try fixtures()
        let clf = try PerchClassifier(url: Self.modelURL, computeUnits: units)
        var agree = 0
        for (w, r) in zip(windows, refs) {
            let out = try clf.classify(w)
            XCTAssertEqual(out.logits.count, 14_795)                 // Perch outputs; labels.json appends BirdNET+-only species after them
            XCTAssertGreaterThanOrEqual(labels.count, out.logits.count)
            let top = Scoring.topK(out.logits, 5)
            if top[0] == r.top1 { agree += 1 } else {
                print("[\(name)] \(r.species): got \(labels[top[0]].scientific), want \(labels[r.top1].scientific)")
            }
            XCTAssertGreaterThanOrEqual(Set(top).intersection(r.top5).count, 4, "\(r.species) top-5 drifted")
            XCTAssertEqual(out.logits[r.top1], r.top1_logit, accuracy: 0.6, "\(r.species) logit drifted")
            XCTAssertEqual(out.spectrogram?.count, 500 * 128)
        }
        print("[\(name)] top-1 agreement \(agree)/\(refs.count)")
        XCTAssertEqual(agree, refs.count)
    }

    func testNeuralEngineMatchesTF() throws { try run(.cpuAndNeuralEngine, name: "ANE") }
    func testGPUMatchesTF() throws { try run(.cpuAndGPU, name: "GPU") }

    func testLabelsCoverLocalMultiTaxa() throws {
        let labels = try fixtures().labels
        XCTAssertEqual(labels.count, 15_335)                 // 14,795 Perch + 540 BirdNET+-only (tools/make_birdnet3_map.py)
        let want: [String: (String, TaxonGroup)] = [
            "Bubo virginianus": ("Great Horned Owl", .bird), "Canis latrans": ("Coyote", .mammal),
            "Sciurus carolinensis": ("Eastern Gray Squirrel", .mammal), "Hyla versicolor": ("Gray Treefrog", .amphibian),
            "Pseudacris crucifer": ("Spring Peeper", .amphibian), "Oecanthus fultoni": ("Snowy Tree Cricket", .insect),
        ]
        for (s, (c, g)) in want {
            let l = labels[try XCTUnwrap(labels.index(ofScientific: s), s)]
            XCTAssertEqual(l.common, c); XCTAssertEqual(l.group, g, s)
        }
    }
}
