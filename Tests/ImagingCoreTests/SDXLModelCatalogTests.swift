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

    // MARK: - Phase A.3 LoRA variant

    func test_loraColoring_hasValidDownloadURL() {
        let url = SDXLModelCatalog.Variant.loraColoring.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "apps.softwareasan.ai")
        XCTAssertTrue(url.path.hasPrefix("/genesis-imaging/models/"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".zip"))
    }

    func test_loraColoring_sha256_pinned() {
        guard let sha = SDXLModelCatalog.Variant.loraColoring.sha256 else {
            XCTFail("LoRA SHA256 must be pinned — bundle uploaded 2026-05-17")
            return
        }
        XCTAssertEqual(sha.count, 64)
        XCTAssertEqual(
            sha,
            "c676295a9492f84455abca80355c116f41c5eac0d47f8c8a18a88c03c695f136",
            "LoRA pin must match the bundle currently served at apps.softwareasan.ai"
        )
    }

    func test_loraColoring_expectedSizeBytes() {
        // Verified via local stat -f %z + remote stat -c %s before pin.
        XCTAssertEqual(SDXLModelCatalog.Variant.loraColoring.expectedSizeBytes, 6_432_524_320)
    }

    func test_loraColoring_versionMarker_identifiesLoRA() {
        let marker = SDXLModelCatalog.Variant.loraColoring.versionMarker
        XCTAssertTrue(marker.contains("lora"), "LoRA variant marker must advertise LoRA")
        XCTAssertTrue(marker.contains("coloringbookredmond"),
                      "Marker should reference the specific LoRA we fused")
    }

    func test_loraColoring_includesVAEEncoder() {
        // VAE encoder enables img2img (eraser → inpainting workflow). Apple's
        // base palettized bundle does NOT ship VAEEncoder — only our LoRA
        // variant does (converted with --convert-vae-encoder in Step 2).
        let required = SDXLModelCatalog.Variant.loraColoring.requiredEntries
        XCTAssertTrue(required.contains("VAEEncoder.mlmodelc"),
                      "LoRA bundle must ship VAEEncoder for img2img")
        XCTAssertFalse(SDXLModelCatalog.Variant.palettized.requiredEntries.contains("VAEEncoder.mlmodelc"),
                       "Apple base bundle does not include VAEEncoder")
    }

    func test_loraColoring_resourcesSubpath_matchesUploadedZipLayout() {
        // Mirrors the layout package-and-upload.sh staged into the zip:
        //   <top>/coreml-stable-diffusion-xl-coloring-book_compiled/compiled/*
        XCTAssertEqual(
            SDXLModelCatalog.Variant.loraColoring.resourcesSubpath,
            "coreml-stable-diffusion-xl-coloring-book_compiled/compiled"
        )
    }

    func test_loraColoring_defaultPrompt_includesLoRATriggerWords() {
        // CivitAI model card specifies "ColoringBookAF, Coloring Book" as the
        // trigger phrase that activates the LoRA strongly. The default prompt
        // must prepend them so out-of-box generation honors the LoRA.
        let prompt = SDXLModelCatalog.Variant.loraColoring.defaultPrompt
        XCTAssertTrue(prompt.contains("ColoringBookAF"),
                      "LoRA defaultPrompt must include 'ColoringBookAF' trigger")
        XCTAssertTrue(prompt.contains("Coloring Book"),
                      "LoRA defaultPrompt must include 'Coloring Book' trigger")
    }

    func test_isUserSelectable_picksProductionVariantsOnly() {
        XCTAssertTrue(SDXLModelCatalog.Variant.palettized.isUserSelectable)
        XCTAssertTrue(SDXLModelCatalog.Variant.loraColoring.isUserSelectable)
        XCTAssertFalse(SDXLModelCatalog.Variant.base.isUserSelectable,
                       "Base variant has no pinned SHA → not shippable to users yet")
        XCTAssertFalse(SDXLModelCatalog.Variant.iosSplitEinsum.isUserSelectable,
                       "iOS split-einsum is dev-only on macOS")
    }

    func test_humanLabel_paletizedRenamedToAppleBase() {
        // v0.5.0.0: when two variants coexist in the picker, "Palettized" alone
        // is jargon. Renamed to "Apple Base SDXL" for customer clarity. The
        // LoRA variant gets the more descriptive "Çocuk Boyama Kitabı (LoRA)".
        XCTAssertEqual(SDXLModelCatalog.Variant.palettized.humanLabel, "Apple Base SDXL")
        XCTAssertEqual(SDXLModelCatalog.Variant.loraColoring.humanLabel, "Çocuk Boyama Kitabı (LoRA)")
    }
}
