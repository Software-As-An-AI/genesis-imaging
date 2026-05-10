import Foundation

/// Describes one tile in a non-overlapping image grid. Used by `CoreMLEngine`
/// to split large input images into fixed-size chunks for models like
/// `RealESRGAN_x4plus.mlmodel` whose input shape is hard-pinned at 512×512.
///
/// Edge tiles have the same engine-side size (`tileSize × tileSize`); the
/// caller pads the input region (e.g. via edge-replicate) and crops the
/// upscaled output back to `(inputWidth × scale, inputHeight × scale)`.
public struct TileSpec: Sendable, Equatable {
    public let index: Int
    public let column: Int
    public let row: Int
    /// Pixel where this tile starts in the *input* image (multiples of `tileSize`).
    public let inputOriginX: Int
    public let inputOriginY: Int
    /// Pixel where this tile's output should be pasted in the *output* canvas
    /// (multiples of `tileSize * scale`).
    public let outputOriginX: Int
    public let outputOriginY: Int
    /// How many input pixels in this tile correspond to real image content.
    /// For interior tiles: equal to the configured `tileSize`. For right/bottom
    /// edge tiles on non-multiple dimensions: less than `tileSize`. The remaining
    /// area inside the engine input must be padded by the caller.
    public let inputContentWidth: Int
    public let inputContentHeight: Int

    public init(index: Int, column: Int, row: Int,
                inputOriginX: Int, inputOriginY: Int,
                outputOriginX: Int, outputOriginY: Int,
                inputContentWidth: Int, inputContentHeight: Int) {
        self.index = index
        self.column = column
        self.row = row
        self.inputOriginX = inputOriginX
        self.inputOriginY = inputOriginY
        self.outputOriginX = outputOriginX
        self.outputOriginY = outputOriginY
        self.inputContentWidth = inputContentWidth
        self.inputContentHeight = inputContentHeight
    }
}

/// Plan for splitting an input image into tiles + assembling outputs back into a canvas.
public struct TileGrid: Sendable {
    public let columns: Int
    public let rows: Int
    public let tileSize: Int
    public let scale: Int
    /// Real pixel dimensions of the input image (before any padding).
    public let inputWidth: Int
    public let inputHeight: Int
    /// Final output dimensions after cropping (always `inputWidth * scale`, `inputHeight * scale`).
    public let outputWidth: Int
    public let outputHeight: Int
    public let tiles: [TileSpec]

    public var totalTiles: Int { tiles.count }

    public init(columns: Int, rows: Int, tileSize: Int, scale: Int,
                inputWidth: Int, inputHeight: Int, tiles: [TileSpec]) {
        self.columns = columns
        self.rows = rows
        self.tileSize = tileSize
        self.scale = scale
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = inputWidth * scale
        self.outputHeight = inputHeight * scale
        self.tiles = tiles
    }
}

public enum TileSplitter {
    /// Compute a tile grid that fully covers an `inputWidth × inputHeight` image
    /// using non-overlapping `tileSize × tileSize` chunks.
    ///
    /// - Parameters:
    ///   - width: Input image width in pixels.
    ///   - height: Input image height in pixels.
    ///   - tileSize: Engine-side tile dimension (default 512, matches `RealESRGAN_x4plus.mlmodel`).
    ///   - scale: Upscale factor (default 4 for x4plus model).
    /// - Returns: A `TileGrid` listing every tile in row-major (top-left → bottom-right) order.
    public static func grid(forImageWidth width: Int, height: Int,
                            tileSize: Int = 512, scale: Int = 4) -> TileGrid {
        precondition(width > 0 && height > 0, "image dimensions must be positive")
        precondition(tileSize > 0, "tileSize must be positive")
        precondition(scale > 0, "scale must be positive")

        let columns = max(1, (width + tileSize - 1) / tileSize)
        let rows = max(1, (height + tileSize - 1) / tileSize)

        var tiles: [TileSpec] = []
        tiles.reserveCapacity(columns * rows)

        var index = 0
        for row in 0..<rows {
            let inputOriginY = row * tileSize
            let remainingHeight = height - inputOriginY
            let inputContentHeight = min(tileSize, remainingHeight)
            let outputOriginY = inputOriginY * scale

            for column in 0..<columns {
                let inputOriginX = column * tileSize
                let remainingWidth = width - inputOriginX
                let inputContentWidth = min(tileSize, remainingWidth)
                let outputOriginX = inputOriginX * scale

                tiles.append(TileSpec(
                    index: index,
                    column: column,
                    row: row,
                    inputOriginX: inputOriginX,
                    inputOriginY: inputOriginY,
                    outputOriginX: outputOriginX,
                    outputOriginY: outputOriginY,
                    inputContentWidth: inputContentWidth,
                    inputContentHeight: inputContentHeight
                ))
                index += 1
            }
        }

        return TileGrid(
            columns: columns,
            rows: rows,
            tileSize: tileSize,
            scale: scale,
            inputWidth: width,
            inputHeight: height,
            tiles: tiles
        )
    }
}
