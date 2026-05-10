import Foundation
import CoreML
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ImagingCore

/// Faz 2 implementation — drives `RealESRGAN_x4plus.mlmodel` (neuralNetwork v4
/// spec, fixed 512×512 RGB input → 2048×2048 RGB output) through Core ML with
/// `compute_units = .all` so the runtime can opportunistically delegate to ANE.
///
/// Large images are tiled into non-overlapping 512×512 chunks via `TileSplitter`,
/// each tile predicted independently, then the outputs are pasted back into a
/// canvas sized `(width × scale, height × scale)`.
///
/// Empirical (Step 0 spike, M4 Pro, 512×512 → 2048×2048 single tile):
/// ncnn-vulkan ~3.17 s · Core ML `.all` ~0.61 s (5.2× faster).
public final class CoreMLEngine: UpscaleEngine, @unchecked Sendable {
    public let engineName = "coreml"
    public let supportedModels = ["realesrgan-x4plus"]

    public func supportsScale(_ scale: Int) -> Bool { scale == 4 }

    /// Pinned tile size — `RealESRGAN_x4plus.mlmodel` is hard-shaped at 512×512.
    public static let tileSize = 512
    public static let inputFeatureName = "input"
    public static let outputFeatureName = "activation_out"

    private let modelURL: URL
    private let model: MLModel
    private let computeUnitsName: String

    public init(modelURL: URL? = nil) throws {
        self.modelURL = try (modelURL ?? ModelLocator.defaultModelURL())
        try ModelLocator.validate(modelURL: self.modelURL)

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all  // ANE preferred → GPU → CPU
        self.computeUnitsName = "all"

        do {
            self.model = try MLModel(contentsOf: self.modelURL, configuration: configuration)
        } catch {
            throw UpscaleError.ioError(message: "Failed to load Core ML model at \(self.modelURL.path): \(error)")
        }
    }

    public func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error> {
        AsyncThrowingStream { continuation in
            let model = self.model
            DispatchQueue.global(qos: .userInitiated).async {
                Self.runUpscale(request: request, model: model, continuation: continuation)
            }
        }
    }

    public func probe() async throws -> EngineHealth {
        EngineHealth(
            isAvailable: true,
            version: "core-ml-realesrgan-mszpro-2024-07-15",
            detectedDevice: "Apple Silicon (compute_units=\(computeUnitsName))"
        )
    }

    // MARK: - Pipeline

    private static func runUpscale(
        request: UpscaleRequest,
        model: MLModel,
        continuation: AsyncThrowingStream<UpscaleProgress, Error>.Continuation
    ) {
        let startTime = Date()
        continuation.yield(.started)

        do {
            guard request.scale == 4 else {
                throw UpscaleError.unsupportedFormat(mediaType: "scale=\(request.scale) (only 4 supported)")
            }

            // 1. Load input image
            let inputCGImage = try loadCGImage(from: request.inputURL)
            let inputWidth = inputCGImage.width
            let inputHeight = inputCGImage.height
            let inputBytes = fileSize(at: request.inputURL)

            // 2. Plan tile grid
            let grid = TileSplitter.grid(
                forImageWidth: inputWidth, height: inputHeight,
                tileSize: tileSize, scale: request.scale
            )

            continuation.yield(.tile(current: 0, total: grid.totalTiles))

            // 3. Prepare output canvas
            let outputContext = try makeOutputContext(width: grid.outputWidth, height: grid.outputHeight)

            // 4. Process tiles sequentially (in-flight Core ML predict isn't externally cancellable;
            //    we honor Task.isCancelled at tile boundaries).
            for tile in grid.tiles {
                if Task.isCancelled {
                    continuation.finish(throwing: UpscaleError.cancelled)
                    return
                }

                let outputTileImage = try predictTile(
                    inputCGImage: inputCGImage,
                    tile: tile,
                    tileSize: tileSize,
                    model: model
                )

                // Paste only the actual content area (drop any padded margin in output)
                pasteTileOutput(
                    outputTileImage,
                    into: outputContext,
                    tile: tile,
                    scale: request.scale,
                    canvasHeight: grid.outputHeight
                )

                continuation.yield(.tile(current: tile.index + 1, total: grid.totalTiles))
            }

            // 5. Finalize canvas → PNG
            try writeContextToPNG(outputContext, url: request.outputURL)

            let outputBytes = fileSize(at: request.outputURL)
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let result = UpscaleResult(
                outputURL: request.outputURL,
                inputBytes: inputBytes,
                outputBytes: outputBytes,
                durationMs: durationMs,
                engineName: "core-ml-realesrgan-mszpro"
            )
            continuation.yield(.completed(result))
            continuation.finish()
        } catch let err as UpscaleError {
            continuation.finish(throwing: err)
        } catch {
            continuation.finish(throwing: UpscaleError.engineFailure(
                exitCode: -1, stderr: "\(error)"
            ))
        }
    }

    // MARK: - Image loading / saving

    private static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw UpscaleError.ioError(message: "CGImageSource create failed for \(url.path)")
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw UpscaleError.ioError(message: "CGImage extraction failed for \(url.path)")
        }
        return cgImage
    }

    private static func makeOutputContext(width: Int, height: Int) throws -> CGContext {
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 =
            CGImageAlphaInfo.noneSkipLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw UpscaleError.ioError(message: "CGContext allocation failed (\(width)×\(height))")
        }
        return context
    }

    private static func writeContextToPNG(_ context: CGContext, url: URL) throws {
        guard let image = context.makeImage() else {
            throw UpscaleError.ioError(message: "Output canvas → CGImage failed")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw UpscaleError.ioError(message: "CGImageDestination create failed for \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.ioError(message: "PNG finalize failed for \(url.path)")
        }
    }

    // MARK: - Tile prediction

    private static func predictTile(
        inputCGImage: CGImage,
        tile: TileSpec,
        tileSize: Int,
        model: MLModel
    ) throws -> CGImage {
        let tileInputCGImage = try buildTileInputCGImage(
            inputCGImage: inputCGImage, tile: tile, tileSize: tileSize
        )

        let featureValue = try MLFeatureValue(
            cgImage: tileInputCGImage,
            pixelsWide: tileSize,
            pixelsHigh: tileSize,
            pixelFormatType: kCVPixelFormatType_32BGRA,
            options: nil
        )

        let provider = try MLDictionaryFeatureProvider(dictionary: [inputFeatureName: featureValue])
        let prediction = try model.prediction(from: provider)

        guard let outputBuffer = prediction.featureValue(for: outputFeatureName)?.imageBufferValue else {
            throw UpscaleError.engineFailure(
                exitCode: -1,
                stderr: "Core ML output missing '\(outputFeatureName)' image buffer"
            )
        }

        return try cgImage(from: outputBuffer)
    }

    /// Compose a 512×512 BGRA CGImage from the input image's tile region.
    /// Edge tiles (smaller real content) are placed top-left and the remaining area
    /// is filled with opaque black. The output canvas paste step crops away the
    /// padded region, so any model artefacts in the padded zone never reach disk.
    private static func buildTileInputCGImage(
        inputCGImage: CGImage,
        tile: TileSpec,
        tileSize: Int
    ) throws -> CGImage {
        // CGImage uses an inverted Y axis compared to image-pixel coordinates,
        // so crop with the source rect in image-pixel space.
        let sourceRect = CGRect(
            x: tile.inputOriginX,
            y: tile.inputOriginY,
            width: tile.inputContentWidth,
            height: tile.inputContentHeight
        )
        guard let cropped = inputCGImage.cropping(to: sourceRect) else {
            throw UpscaleError.ioError(message: "CGImage.cropping failed for tile \(tile.index)")
        }

        // Fast path: content already fills the full tile, return cropping as-is.
        if tile.inputContentWidth == tileSize && tile.inputContentHeight == tileSize {
            return cropped
        }

        // Slow path: edge tile, need a padded canvas.
        let bitmapInfo: UInt32 =
            CGImageAlphaInfo.noneSkipLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: tileSize, height: tileSize,
            bitsPerComponent: 8,
            bytesPerRow: tileSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw UpscaleError.ioError(message: "Tile pad context allocation failed")
        }

        // Fill with opaque black baseline
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))

        // CGContext draws bottom-up; place content so that pixel (0,0) of the
        // input lands at pixel (0,0) of the output buffer (= top-left). For a
        // 512-tall buffer, that means drawing at y = (512 - contentHeight).
        let drawRect = CGRect(
            x: 0,
            y: tileSize - tile.inputContentHeight,
            width: tile.inputContentWidth,
            height: tile.inputContentHeight
        )
        context.draw(cropped, in: drawRect)

        guard let padded = context.makeImage() else {
            throw UpscaleError.ioError(message: "Padded tile makeImage failed")
        }
        return padded
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext(options: nil)
        guard let outputImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw UpscaleError.ioError(message: "CIImage → CGImage conversion failed for output")
        }
        return outputImage
    }

    /// Paste only the real-content region of a tile's output into the output canvas.
    /// `tile.outputOrigin*` is in image-pixel (top-left) coordinates; Core Graphics
    /// uses bottom-left so we transform once on the destination Y.
    private static func pasteTileOutput(
        _ tileOutputCGImage: CGImage,
        into context: CGContext,
        tile: TileSpec,
        scale: Int,
        canvasHeight: Int
    ) {
        let outputContentWidth = tile.inputContentWidth * scale
        let outputContentHeight = tile.inputContentHeight * scale

        // 1. Crop the model output to just the real-content area (top-left corner).
        //    Padded edges are ignored.
        let cropRect = CGRect(
            x: 0,
            y: 0,
            width: outputContentWidth,
            height: outputContentHeight
        )
        guard let croppedOutput = tileOutputCGImage.cropping(to: cropRect) else {
            return
        }

        // 2. Place into output canvas at the right pixel coordinates.
        //    Image-pixel Y (top-left origin) → CGContext Y (bottom-left origin):
        //      cgY = canvasHeight - (pixelY + contentHeight)
        let cgY = canvasHeight - (tile.outputOriginY + outputContentHeight)
        let destRect = CGRect(
            x: tile.outputOriginX,
            y: cgY,
            width: outputContentWidth,
            height: outputContentHeight
        )
        context.draw(croppedOutput, in: destRect)
    }

    // MARK: - Misc

    private static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
