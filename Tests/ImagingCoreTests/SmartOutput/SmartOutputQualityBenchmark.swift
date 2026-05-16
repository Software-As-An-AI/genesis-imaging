import XCTest
@testable import ImagingCore

/// Quantitative quality benchmark: v0.3.3.0 vs v0.3.3.1 despeckle behavior.
///
/// Operator concern (2026-05-15): "upscale kalitesi bozulmuş gibi geliyor".
/// First-order observation: engine code (NcnnEngine + CoreMLEngine +
/// ContentDetector + ContentFingerprint) is bit-identical across both
/// releases — only Smart Output post-process changed.
///
/// This benchmark synthesizes a controlled "character" fixture (large body +
/// small mouth detail + dust artifact) and runs both v0.3.3.0 and v0.3.3.1
/// behavior, emitting metrics:
///
///   1. **Detail preservation** — black pixels of real features that survive
///   2. **Artifact cleanup** — dust/noise pixels cleared
///   3. **False destruction** — real features wrongly removed (REGRESSION)
///
/// Output: stdout markdown table the operator can paste anywhere. Always
/// passes; this is a measurement tool, not a pass/fail gate.
final class SmartOutputQualityBenchmark: XCTestCase {

    /// 64×64 fixture composing the failure modes Nadezhda reported:
    ///   - Body: 20×20 = 400 px (the main character)
    ///   - Mouth: 4×5 = 20 px (isolated small feature)
    ///   - Eyebrow: 3×4 = 12 px (smaller isolated feature)
    ///   - Tear: 2×3 = 6 px (very small feature)
    ///   - Dust 1: 3 px isolated cluster
    ///   - Dust 2: 1 px isolated speckle
    private func makeBenchmarkFixture() -> (buffer: [UInt8], width: Int, height: Int) {
        let w = 64, h = 64
        var buf = [UInt8](repeating: 255, count: w * h)
        // Body (400 px) — large blob, top-left quadrant
        for y in 5..<25 { for x in 5..<25 { buf[y * w + x] = 0 } }
        // Mouth (20 px) — top-right
        for y in 8..<13 { for x in 40..<44 { buf[y * w + x] = 0 } }
        // Eyebrow (12 px) — bottom-left
        for y in 35..<38 { for x in 10..<14 { buf[y * w + x] = 0 } }
        // Tear (6 px) — bottom-center
        for y in 50..<52 { for x in 30..<33 { buf[y * w + x] = 0 } }
        // Dust 1 (3 px cluster)
        buf[2 * w + 50] = 0; buf[2 * w + 51] = 0; buf[3 * w + 50] = 0
        // Dust 2 (1 px speckle)
        buf[55 * w + 60] = 0
        return (buf, w, h)
    }

    /// Run despeckle with given threshold + classify pixels.
    private struct Metrics {
        var preservedBody: Int = 0    // out of 400
        var preservedMouth: Int = 0    // out of 20
        var preservedEyebrow: Int = 0  // out of 12
        var preservedTear: Int = 0     // out of 6
        var dustCleared: Int = 0       // out of 4 dust pixels
        var totalBlack: Int = 0
    }

    private func measure(buffer: [UInt8], width w: Int, height h: Int) -> Metrics {
        var m = Metrics()
        // Body region: rows 5..25, cols 5..25
        for y in 5..<25 { for x in 5..<25 where buffer[y * w + x] <= 128 { m.preservedBody += 1 } }
        // Mouth region: rows 8..13, cols 40..44
        for y in 8..<13 { for x in 40..<44 where buffer[y * w + x] <= 128 { m.preservedMouth += 1 } }
        // Eyebrow: rows 35..38, cols 10..14
        for y in 35..<38 { for x in 10..<14 where buffer[y * w + x] <= 128 { m.preservedEyebrow += 1 } }
        // Tear: rows 50..52, cols 30..33
        for y in 50..<52 { for x in 30..<33 where buffer[y * w + x] <= 128 { m.preservedTear += 1 } }
        // Dust regions
        let dust1 = [(2, 50), (2, 51), (3, 50)]
        let dust2 = (55, 60)
        for (y, x) in dust1 where buffer[y * w + x] > 128 { m.dustCleared += 1 }
        if buffer[dust2.0 * w + dust2.1] > 128 { m.dustCleared += 1 }
        m.totalBlack = buffer.filter { $0 <= 128 }.count
        return m
    }

    func testEmitQualityMatrix_v0330_vs_v0331() {
        let thresholds: [(version: String, label: String, threshold: Int)] = [
            ("v0.3.3.0", "Soft",   10),
            ("v0.3.3.0", "Normal", 30),
            ("v0.3.3.0", "Strong", 100),
            ("v0.3.3.1", "Soft",   3),
            ("v0.3.3.1", "Normal", 8),
            ("v0.3.3.1", "Strong", 18),
        ]

        print("")
        print("Smart Output Quality Benchmark — v0.3.3.0 vs v0.3.3.1")
        print("Fixture: body 400px + mouth 20px + eyebrow 12px + tear 6px + dust 4px")
        print("")
        print("Version  | Preset | Thresh | Body | Mouth | Eyebrow | Tear | Dust")

        for entry in thresholds {
            var (buf, w, h) = makeBenchmarkFixture()
            DespeckleFilter.despeckleGrayscale(
                buffer: &buf, width: w, height: h, maxBlobArea: entry.threshold
            )
            let m = measure(buffer: buf, width: w, height: h)
            let line = "\(entry.version) | \(entry.label.padding(toLength: 6, withPad: " ", startingAt: 0)) | "
                + "\(entry.threshold)    | "
                + "\(m.preservedBody)/400 | \(m.preservedMouth)/20 | "
                + "\(m.preservedEyebrow)/12 | \(m.preservedTear)/6 | "
                + "\(m.dustCleared)/4"
            print(line)
        }
        print("")

        XCTAssertTrue(true)
    }
}
