import XCTest
@testable import NcnnEngine

final class NcnnEngineModuleTests: XCTestCase {
    func testPlannedConstants() {
        // Sanity — placeholder constants until full impl lands in Faz 1 Step 4.
        XCTAssertEqual(NcnnEngineModule.plannedEngineName, "ncnn-vulkan")
        XCTAssertEqual(NcnnEngineModule.plannedBinary, "realesrgan-ncnn-vulkan")
        XCTAssertEqual(NcnnEngineModule.plannedVersion, "v0.2.0")
    }
}
