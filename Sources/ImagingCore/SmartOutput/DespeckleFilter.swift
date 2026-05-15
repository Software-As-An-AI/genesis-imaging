import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - DespecklePreset

/// Aggressiveness preset for `DespeckleFilter` — controls the **max area**
/// (pixel count) of an isolated black connected-component that's treated
/// as "noise" and cleared to white.
///
/// Calibration baseline (2026-05-16, empirical refinement pending in Phase B):
///   - `.soft`: very small artifacts only, anti-alias edges safe
///   - `.normal`: default, covers typical ncnn upscale speckle
///   - `.strong`: cleans larger artifact clusters at risk of small dot details
public enum DespecklePreset: String, CaseIterable, Codable, Sendable {
    case soft   = "soft"
    case normal = "normal"
    case strong = "strong"

    /// Max connected-component area (in pixels²) classified as "noise".
    /// Components strictly larger than this threshold are preserved.
    public var maxBlobArea: Int {
        switch self {
        case .soft:   return 10
        case .normal: return 30
        case .strong: return 100
        }
    }

    /// Localized label for UI picker.
    public var label: String {
        switch self {
        case .soft:   return "Yumuşak — küçük artifact (1-10 px)"
        case .normal: return "Normal — orta artifact (5-30 px)"
        case .strong: return "Agresif — büyük leke (10-100 px)"
        }
    }

    /// Hint line shown under the picker.
    public var hint: String {
        switch self {
        case .soft:   return "Sadece çok küçük artifact'lar (1-10 pixel)"
        case .normal: return "Küçük siyah leke/noktayı temizler (5-30 pixel)"
        case .strong: return "Daha büyük leke + bant (10-100 pixel)"
        }
    }

    /// Resolve a preset from `@AppStorage` string. Falls back to `.normal`
    /// for unknown values so corrupt persistence can't break the pipeline.
    public static func from(rawValue: String) -> DespecklePreset {
        DespecklePreset(rawValue: rawValue) ?? .normal
    }
}

// MARK: - DespeckleFilter

/// Connected-component analysis (CCA) based noise removal for B/W line art.
///
/// Pipeline (4 stages):
///   1. Decode PNG → grayscale 8-bit bitmap buffer
///   2. Binary threshold pass (luminance ≤ 128 → black, > 128 → white)
///   3. 8-connected BFS labeling → component (id, area) map
///   4. Re-encode: components with `area < preset.maxBlobArea` filled white
///
/// Performance: O(n) where n = pixel count. 5016×5016 typical 250-500ms
/// (single pass + queue ops on minority black pixels in line art).
///
/// Photo content guard: caller responsible for skipping invocation when
/// `ContentFingerprint.nearBinaryScore < 0.85` or color count > 256.
/// See `SmartOutputProcessor` integration.
public enum DespeckleFilter {

    public enum FilterError: Error {
        case decodeFailed(URL)
        case encodeFailed(URL)
        case bufferAllocationFailed
    }

    /// Apply despeckle in-place: read PNG at `url`, write the cleaned
    /// version back to the same URL atomically. Other extended attributes
    /// preserved by the caller's atomic-move flow.
    ///
    /// - Parameter url: PNG file to clean. Must exist + be readable.
    /// - Parameter preset: Aggressiveness preset.
    /// - Throws: `FilterError` on decode/encode failure.
    public static func apply(url: URL, preset: DespecklePreset) throws {
        // 1. Decode PNG → CGImage
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw FilterError.decodeFailed(url)
        }

        // 2. Render to 8-bit grayscale buffer
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width  // 1 byte per pixel for grayscale
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let cs = CGColorSpace(name: CGColorSpace.linearGray)
                ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        else { throw FilterError.bufferAllocationFailed }

        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let ctx = pixels.withUnsafeMutableBufferPointer({ buf -> CGContext? in
            CGContext(
                data: buf.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        }) else { throw FilterError.bufferAllocationFailed }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 3. Run the despeckle pass directly on the grayscale buffer
        despeckleGrayscale(
            buffer: &pixels,
            width: width, height: height,
            maxBlobArea: preset.maxBlobArea
        )

        // 4. Re-encode as PNG (gray colorspace, no alpha)
        try encodeGrayscalePNG(
            buffer: pixels,
            width: width, height: height,
            to: url
        )
    }

    // MARK: - Core CCA pass

    /// Despeckle a grayscale 8-bit buffer in place.
    ///
    /// 1. Threshold (≤ 128 → black, > 128 → white).
    /// 2. BFS-label connected black components (8-connectivity).
    /// 3. For each component with area < maxBlobArea, set its pixels white (255).
    ///
    /// Exposed `internal` for unit testing without PNG round-trip.
    static func despeckleGrayscale(
        buffer: inout [UInt8],
        width: Int, height: Int,
        maxBlobArea: Int
    ) {
        let n = width * height
        precondition(buffer.count == n, "Buffer size mismatch")

        // Step 1: binary classification — UInt8 buffer overload:
        //   0 = white (background), 1 = black-unlabeled, ≥2 = labeled-keep,
        //   We'll repurpose buffer values during BFS for memory thrift.
        // To avoid confusion we allocate a separate label/visit buffer.
        var visited = [Bool](repeating: false, count: n)
        var clearMask = [Bool](repeating: false, count: n)

        // BFS queue reused across components — Int indices into the buffer.
        var queue: [Int] = []
        queue.reserveCapacity(min(1024, n))

        let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
        let dy = [-1, -1, -1, 0, 0, 1, 1, 1]

        for startIdx in 0..<n {
            if visited[startIdx] { continue }
            if buffer[startIdx] > 128 { visited[startIdx] = true; continue }
            // Found a black, unvisited pixel — start BFS for its component.
            queue.removeAll(keepingCapacity: true)
            queue.append(startIdx)
            visited[startIdx] = true
            var componentPixels: [Int] = [startIdx]
            componentPixels.reserveCapacity(64)

            var head = 0
            while head < queue.count {
                let idx = queue[head]
                head += 1
                let x = idx % width
                let y = idx / width
                for k in 0..<8 {
                    let nx = x + dx[k]
                    let ny = y + dy[k]
                    if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                    let nIdx = ny * width + nx
                    if visited[nIdx] { continue }
                    if buffer[nIdx] > 128 {
                        visited[nIdx] = true
                        continue
                    }
                    visited[nIdx] = true
                    queue.append(nIdx)
                    componentPixels.append(nIdx)
                }
            }

            // Component complete. If smaller than threshold → mark for clearing.
            if componentPixels.count < maxBlobArea {
                for idx in componentPixels { clearMask[idx] = true }
            }
        }

        // Step 3: apply mask
        for i in 0..<n where clearMask[i] {
            buffer[i] = 255
        }
    }

    // MARK: - PNG encode helper

    private static func encodeGrayscalePNG(
        buffer: [UInt8],
        width: Int, height: Int,
        to url: URL
    ) throws {
        let cs = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        let bytesPerRow = width
        guard let provider = CGDataProvider(
            data: Data(buffer) as CFData
        ) else { throw FilterError.encodeFailed(url) }

        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw FilterError.encodeFailed(url) }

        guard let dst = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw FilterError.encodeFailed(url) }

        CGImageDestinationAddImage(dst, cgImage, nil)
        guard CGImageDestinationFinalize(dst) else {
            throw FilterError.encodeFailed(url)
        }
    }
}
