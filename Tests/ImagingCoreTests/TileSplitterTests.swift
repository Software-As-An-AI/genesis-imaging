import XCTest
@testable import ImagingCore

final class TileSplitterTests: XCTestCase {

    // MARK: - Exact tile boundaries

    func test_exactSingleTile_512x512_scale4() {
        let grid = TileSplitter.grid(forImageWidth: 512, height: 512, tileSize: 512, scale: 4)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.totalTiles, 1)
        XCTAssertEqual(grid.outputWidth, 2048)
        XCTAssertEqual(grid.outputHeight, 2048)

        let tile = grid.tiles[0]
        XCTAssertEqual(tile.index, 0)
        XCTAssertEqual(tile.column, 0)
        XCTAssertEqual(tile.row, 0)
        XCTAssertEqual(tile.inputOriginX, 0)
        XCTAssertEqual(tile.inputOriginY, 0)
        XCTAssertEqual(tile.outputOriginX, 0)
        XCTAssertEqual(tile.outputOriginY, 0)
        XCTAssertEqual(tile.inputContentWidth, 512)
        XCTAssertEqual(tile.inputContentHeight, 512)
    }

    func test_exactGrid_1024x1024_scale4() {
        let grid = TileSplitter.grid(forImageWidth: 1024, height: 1024, tileSize: 512, scale: 4)
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.totalTiles, 4)
        XCTAssertEqual(grid.outputWidth, 4096)
        XCTAssertEqual(grid.outputHeight, 4096)

        // All tiles fully contented (no padding)
        for tile in grid.tiles {
            XCTAssertEqual(tile.inputContentWidth, 512)
            XCTAssertEqual(tile.inputContentHeight, 512)
        }

        // Spot-check row-major ordering: (col, row) pairs
        XCTAssertEqual(grid.tiles[0].column, 0)
        XCTAssertEqual(grid.tiles[0].row, 0)
        XCTAssertEqual(grid.tiles[1].column, 1)
        XCTAssertEqual(grid.tiles[1].row, 0)
        XCTAssertEqual(grid.tiles[2].column, 0)
        XCTAssertEqual(grid.tiles[2].row, 1)
        XCTAssertEqual(grid.tiles[3].column, 1)
        XCTAssertEqual(grid.tiles[3].row, 1)

        // Output origins line up with 512*4 = 2048 stride
        XCTAssertEqual(grid.tiles[1].outputOriginX, 2048)
        XCTAssertEqual(grid.tiles[2].outputOriginY, 2048)
        XCTAssertEqual(grid.tiles[3].outputOriginX, 2048)
        XCTAssertEqual(grid.tiles[3].outputOriginY, 2048)
    }

    // MARK: - Edge padding

    func test_nonMultiple_600x400_scale4() {
        // 600/512 = 2 cols (covers x=0..511 and x=512..1023, only 88 real cols)
        // 400/512 = 1 row (covers y=0..511, only 400 real rows)
        let grid = TileSplitter.grid(forImageWidth: 600, height: 400, tileSize: 512, scale: 4)
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.totalTiles, 2)
        // Final output should be cropped to input × scale, not padded-tile × scale
        XCTAssertEqual(grid.outputWidth, 2400)
        XCTAssertEqual(grid.outputHeight, 1600)

        // First tile: full width content (left), partial height (400 of 512)
        let left = grid.tiles[0]
        XCTAssertEqual(left.inputOriginX, 0)
        XCTAssertEqual(left.inputOriginY, 0)
        XCTAssertEqual(left.inputContentWidth, 512)   // full tile column
        XCTAssertEqual(left.inputContentHeight, 400)  // image is shorter than tile

        // Second tile: partial width (88), same height (400)
        let right = grid.tiles[1]
        XCTAssertEqual(right.inputOriginX, 512)
        XCTAssertEqual(right.inputOriginY, 0)
        XCTAssertEqual(right.outputOriginX, 2048)
        XCTAssertEqual(right.inputContentWidth, 88)
        XCTAssertEqual(right.inputContentHeight, 400)
    }

    func test_smallerThanTile_100x100() {
        let grid = TileSplitter.grid(forImageWidth: 100, height: 100, tileSize: 512, scale: 4)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.totalTiles, 1)
        XCTAssertEqual(grid.outputWidth, 400)
        XCTAssertEqual(grid.outputHeight, 400)

        let tile = grid.tiles[0]
        XCTAssertEqual(tile.inputContentWidth, 100)
        XCTAssertEqual(tile.inputContentHeight, 100)
        XCTAssertEqual(tile.inputOriginX, 0)
        XCTAssertEqual(tile.inputOriginY, 0)
    }

    // MARK: - Coverage invariants

    func test_tilesCoverEntireImage_noGaps() {
        // For any input dim, tile columns and rows together must cover full extent
        for (w, h) in [(1280, 720), (2048, 1080), (333, 555), (4096, 4096)] {
            let grid = TileSplitter.grid(forImageWidth: w, height: h, tileSize: 512, scale: 4)
            XCTAssertEqual(grid.outputWidth, w * 4)
            XCTAssertEqual(grid.outputHeight, h * 4)

            // Sum of content widths in any row must >= input width (last column may overrun);
            // sum from origin to origin + contentWidth should reach inputWidth.
            let firstRow = grid.tiles.filter { $0.row == 0 }
            let rightmost = firstRow.max { $0.inputOriginX < $1.inputOriginX }!
            XCTAssertEqual(rightmost.inputOriginX + rightmost.inputContentWidth, w,
                "rightmost tile origin + content should reach input width \(w)")

            let firstCol = grid.tiles.filter { $0.column == 0 }
            let bottommost = firstCol.max { $0.inputOriginY < $1.inputOriginY }!
            XCTAssertEqual(bottommost.inputOriginY + bottommost.inputContentHeight, h,
                "bottommost tile origin + content should reach input height \(h)")
        }
    }
}
