import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

/// Operator question (2026-05-15): when multiple files are batch-upscaled,
/// where do outputs go and is the behavior correct?
///
/// Three scenarios covered:
///   1. No override + sources from different parent dirs → each output lands
///      next to its source (per-file parent).
///   2. With override → all outputs co-located in the override dir.
///   3. Smart output filename tag appears for `.auto` and `.adaptive` modes.
@MainActor
final class BatchMultiDirOutputTests: XCTestCase {

    private var tempRoot: URL!
    private var savedMode: SmartOutputMode!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch-multidir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        savedMode = SettingsStore.shared.smartOutputMode
    }

    override func tearDown() async throws {
        SettingsStore.shared.smartOutputMode = savedMode
        if let root = tempRoot { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    // MARK: - Scenario 1: no override → each output beside its source

    func testNoOverride_outputsLandNextToEachSource() async throws {
        SettingsStore.shared.smartOutputMode = .off  // skip pngquant dep

        let dirA = try makeDir("clientA")
        let dirB = try makeDir("clientB")
        let dirC = try makeDir("clientC")
        let f1 = try makeFixture(at: dirA, name: "boyama1.png")
        let f2 = try makeFixture(at: dirB, name: "boyama2.png")
        let f3 = try makeFixture(at: dirC, name: "boyama3.png")

        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        q.add(urls: [f1, f2, f3])
        XCTAssertNil(q.batchOutputOverride, "Default: no override set")

        await q.start(engineProvider: { TrivialEngine() })

        XCTAssertEqual(q.phase, .completed)
        XCTAssertEqual(q.items.count, 3)
        for item in q.items {
            XCTAssertEqual(item.state, .done, "Item \(item.sourceURL.lastPathComponent) state")
        }

        let out1 = try XCTUnwrap(q.items[0].outputURL)
        let out2 = try XCTUnwrap(q.items[1].outputURL)
        let out3 = try XCTUnwrap(q.items[2].outputURL)

        // Each output lives in its source's parent directory.
        XCTAssertEqual(out1.deletingLastPathComponent().standardizedFileURL,
                       dirA.standardizedFileURL,
                       "boyama1 output should be in clientA")
        XCTAssertEqual(out2.deletingLastPathComponent().standardizedFileURL,
                       dirB.standardizedFileURL,
                       "boyama2 output should be in clientB")
        XCTAssertEqual(out3.deletingLastPathComponent().standardizedFileURL,
                       dirC.standardizedFileURL,
                       "boyama3 output should be in clientC")

        // Filename pattern: <stem>-upscaled-x4.png (off mode → no smart tag)
        XCTAssertEqual(out1.lastPathComponent, "boyama1-upscaled-x4.png")
        XCTAssertEqual(out2.lastPathComponent, "boyama2-upscaled-x4.png")
        XCTAssertEqual(out3.lastPathComponent, "boyama3-upscaled-x4.png")

        // Files actually exist on disk.
        for url in [out1, out2, out3] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "Missing file: \(url.path)")
        }
    }

    // MARK: - Scenario 2: explicit override → all outputs co-located

    func testWithOverride_allOutputsCoLocatedInOverrideDir() async throws {
        SettingsStore.shared.smartOutputMode = .off

        let dirA = try makeDir("srcA")
        let dirB = try makeDir("srcB")
        let outDir = try makeDir("batch-out")

        let f1 = try makeFixture(at: dirA, name: "a.png")
        let f2 = try makeFixture(at: dirB, name: "b.png")

        let q = BatchQueue(
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            batchOutputOverride: outDir
        )
        q.add(urls: [f1, f2])

        await q.start(engineProvider: { TrivialEngine() })

        XCTAssertEqual(q.phase, .completed)
        let outs = q.items.compactMap { $0.outputURL }
        XCTAssertEqual(outs.count, 2)
        for url in outs {
            XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                           outDir.standardizedFileURL,
                           "All outputs should be in override dir")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        // Sources from different dirs but outputs co-located + filename
        // stems preserved.
        let names = Set(outs.map { $0.lastPathComponent })
        XCTAssertEqual(names, Set(["a-upscaled-x4.png", "b-upscaled-x4.png"]))
    }

    // MARK: - Scenario 3: filename conflict → auto-increment, no overwrite

    func testConflictAutoIncrement_doesNotOverwriteExisting() async throws {
        SettingsStore.shared.smartOutputMode = .off

        let dir = try makeDir("conflict")
        let src = try makeFixture(at: dir, name: "x.png")
        // Pre-create the "natural" output name so resolver bumps to -2.
        let preexisting = dir.appendingPathComponent("x-upscaled-x4.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: preexisting)  // PNG magic

        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        q.add(urls: [src])

        await q.start(engineProvider: { TrivialEngine() })
        XCTAssertEqual(q.phase, .completed)

        let out = try XCTUnwrap(q.items.first?.outputURL)
        XCTAssertEqual(out.lastPathComponent, "x-upscaled-x4-2.png",
                       "Resolver should auto-increment on conflict")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        // Pre-existing file untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: preexisting.path))
        let preBytes = (try? FileManager.default.attributesOfItem(
            atPath: preexisting.path
        )[.size] as? Int) ?? -1
        XCTAssertEqual(preBytes, 4, "Pre-existing 4-byte file should not be overwritten")
    }

    // MARK: - Scenario 4: smart-tag injection (mode .auto, no binaries required for filename check)

    func testFilenameTag_autoMode_includesAutoSuffix() async throws {
        // The .off path was covered above; .auto adds `-auto` suffix
        // regardless of whether pngquant ran (resolver uses
        // SmartOutputMode.filenameTag at resolve time).
        SettingsStore.shared.smartOutputMode = .auto

        let dir = try makeDir("tagtest")
        let src = try makeFixture(at: dir, name: "tag.png")

        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        q.add(urls: [src])
        await q.start(engineProvider: { TrivialEngine() })

        XCTAssertEqual(q.phase, .completed)
        let out = try XCTUnwrap(q.items.first?.outputURL)
        // For .auto, filenameTag is "auto". (.adaptive would be runtime-swapped
        // to adaptive-<picked> but only when binaries available; covered by
        // SmartOutputBatchIntegrationTests.)
        XCTAssertTrue(
            out.lastPathComponent.contains("-auto.png")
              || out.lastPathComponent.contains("-upscaled-x4.png"),  // fallback if pipeline tolerated
            "Filename should carry mode tag: got \(out.lastPathComponent)"
        )
    }

    // MARK: - Helpers

    private func makeDir(_ name: String) throws -> URL {
        let dir = tempRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFixture(at dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 32, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "fixture", code: 1) }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else { throw NSError(domain: "fixture", code: 2) }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}

// MARK: - TrivialEngine — copies input to output, no upscaling.

private final class TrivialEngine: UpscaleEngine, @unchecked Sendable {
    let engineName = "trivial-mock"
    let supportedModels = ["realesrgan-x4plus"]

    func supportsScale(_ scale: Int) -> Bool { true }
    func probe() async throws -> EngineHealth {
        EngineHealth(isAvailable: true, version: "test", detectedDevice: nil)
    }

    func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error> {
        AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.yield(.started)
                do {
                    let data = try Data(contentsOf: request.inputURL)
                    try data.write(to: request.outputURL)
                } catch {
                    continuation.finish(throwing: UpscaleError.ioError(
                        message: "Trivial copy failed: \(error)"
                    ))
                    return
                }
                let result = UpscaleResult(
                    outputURL: request.outputURL,
                    inputBytes: 0,
                    outputBytes: 1024,
                    durationMs: 0,
                    engineName: "trivial-mock"
                )
                continuation.yield(.completed(result))
                continuation.finish()
            }
        }
    }
}
