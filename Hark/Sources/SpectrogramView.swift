import SwiftUI
import CoreGraphics

/// The newest 5 s window as Perch sees it: 500 frames x 128 mel bins (low frequencies at the bottom).
struct SpectrogramView: View {
    let values: [Float]?
    var body: some View {
        ZStack {
            Color.black
            if let img = values.flatMap(Self.image) {
                Image(decorative: img, scale: 1).resizable().interpolation(.medium)
            } else {
                Text("Spectrogram").font(.caption).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // Perch spectrogram = 0.1*log(max(mel, 1e-5)) -> floor about -1.151. Scale each window to its own range.
    static func image(_ v: [Float]) -> CGImage? {
        let frames = 500, bins = 128
        guard v.count == frames * bins else { return nil }
        let lo: Float = -1.151
        let hi = max(v.max() ?? lo, lo + 0.25)
        var px = [UInt8](repeating: 0, count: frames * bins * 4)
        for f in 0..<frames {
            for b in 0..<bins {
                let t = min(max((v[f * bins + b] - lo) / (hi - lo), 0), 1)
                let (r, g, bl) = palette(t)
                let o = ((bins - 1 - b) * frames + f) * 4
                px[o] = r; px[o + 1] = g; px[o + 2] = bl; px[o + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: frames, height: bins, bitsPerComponent: 8, bytesPerRow: frames * 4,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    // Dark blue -> teal -> yellow (perceptually ordered, readable on black).
    static func palette(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let stops: [(Float, Float, Float)] = [(0.02, 0.02, 0.08), (0.10, 0.20, 0.45), (0.10, 0.55, 0.55), (0.55, 0.80, 0.30), (0.99, 0.91, 0.15)]
        let x = t * Float(stops.count - 1)
        let i = min(Int(x), stops.count - 2), f = x - Float(i)
        let a = stops[i], b = stops[i + 1]
        func c(_ p: Float, _ q: Float) -> UInt8 { UInt8(max(0, min(255, (p + (q - p) * f) * 255))) }
        return (c(a.0, b.0), c(a.1, b.1), c(a.2, b.2))
    }
}
