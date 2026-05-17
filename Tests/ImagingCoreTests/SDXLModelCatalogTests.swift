import XCTest
@testable import ImagingCore

final class SDXLModelCatalogTests: XCTestCase {

    func test_defaultVariant_isPalettized() {
        // Ship contract: palettized is the only pinned + ready variant for v1.
        XCTAssertEqual(SDXLModelCatalog.defaultVariant, .palettized)
    }

    func test_palettized_hasValidDownloadURL() {
        let v: SDXLModelCatalog.Variant = .palettized
        let url = v.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(url.path.contains("mixed-bit-palettization"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".zip"))
    }

    func test_palettized_sha256_is64HexChars() {
        guard let sha = SDXLModelCatalog.Variant.palettized.sha256 else {
            XCTFail("Palettized SHA256 must be pinned for v1 ship")
            return
        }
        XCTAssertEqual(sha.count, 64, "SHA256 hex must be exactly 64 chars")
        let hexCharset = CharacterSet(charactersIn: "0123456789abcdef")
        let badChars = sha.unicodeScalars.filter { !hexCharset.contains($0) }
        XCTAssertTrue(badChars.isEmpty, "SHA256 must contain only lowercase hex: bad=\(badChars)")
    }

    func test_palettized_expectedSizeBytes_matchesUpstream() {
        // Pinned from HF x-linked-size header 2026-05-17.
        XCTAssertEqual(SDXLModelCatalog.Variant.palettized.expectedSizeBytes, 6_711_666_087)
    }

    func test_palettized_versionMarker_format() {
        // Should NOT contain "lora" — Phase A.2 ships prompt-only, LoRA deferred to A.3.
        let marker = SDXLModelCatalog.Variant.palettized.versionMarker
        XCTAssertFalse(marker.contains("lora"), "v1 marker must not advertise LoRA")
        XCTAssertTrue(marker.contains("palettized"), "Marker should reflect variant identity")
    }

    func test_requiredEntries_includeAppleCasing() {
        // Catches the v0.4.0.x scaffold bug where we required "VaeDecoder" but
        // Apple's bundle ships "VAEDecoder" (all-caps VAE).
        let required = SDXLModelCatalog.Variant.palettized.requiredEntries
        XCTAssertTrue(required.contains("VAEDecoder.mlmodelc"))
        XCTAssertFalse(required.contains("VaeDecoder.mlmodelc"),
                       "Bug: 'VaeDecoder' was Phase A.1 typo — Apple uses 'VAEDecoder'")
        XCTAssertTrue(required.contains("vocab.json"))
        XCTAssertTrue(required.contains("merges.txt"))
    }
}
