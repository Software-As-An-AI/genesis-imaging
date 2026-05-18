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

    // MARK: - Phase A.4 EngineKind + .fluxKlein variant

    func test_engineKind_sdxlVariantsAreCoreML() {
        for v in [SDXLModelCatalog.Variant.palettized,
                  .base,
                  .iosSplitEinsum,
                  .loraColoring] {
            XCTAssertEqual(v.engineKind, .coreMLSDXL,
                           "\(v) must dispatch to Core ML engine")
        }
    }

    func test_engineKind_fluxVariantIsMLX() {
        XCTAssertEqual(SDXLModelCatalog.Variant.fluxKlein.engineKind, .mlxFlux,
                       "FLUX Klein must dispatch to MLX engine")
    }

    func test_fluxKlein_humanLabelAdvertisesExperimental() {
        // Honest framing: FLUX is "preview-class commercial illustration"
        // per research. UI label must signal that explicitly so customers
        // don't expect DALL-E parity.
        let label = SDXLModelCatalog.Variant.fluxKlein.humanLabel
        XCTAssertTrue(label.contains("FLUX"))
        XCTAssertTrue(label.lowercased().contains("deneysel"),
                      "Label must signal experimental status, got: \(label)")
    }

    func test_fluxKlein_notUserSelectableUntilStep6() {
        // Phase A.4 sequential ship: variant exists in catalog from Step 1
        // but stays gated from UI until multi-file download (Step 3) +
        // MLX engine (Step 4) + Settings picker extension (Step 6) land.
        XCTAssertFalse(SDXLModelCatalog.Variant.fluxKlein.isUserSelectable,
                       "FLUX Klein must stay gated until Step 6 unlocks it")
    }

    func test_fluxKlein_downloadURLPointsAtHF() {
        // Phase A.4 lockdown #3: HF direct primary (anonymous-pull OK,
        // no token needed). Step 3 multi-file refactor adds VAE + Qwen3 URLs.
        let url = SDXLModelCatalog.Variant.fluxKlein.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(url.path.contains("black-forest-labs/FLUX.2-klein-4B"))
    }

    func test_fluxKlein_versionMarkerIdentifiesFLUX() {
        let marker = SDXLModelCatalog.Variant.fluxKlein.versionMarker
        XCTAssertTrue(marker.contains("fluxklein"))
        XCTAssertTrue(marker.contains("qwen3"),
                      "Marker should reference text encoder pinned (Qwen3)")
    }

    func test_fluxKlein_defaultPromptIsMinimal() {
        // Klein 4B produces coloring-book aesthetic natively without
        // SDXL-style stylistic prompt scaffolding. defaultPrompt is a
        // bare subject sentence — no "thick black outline / vector style"
        // because Klein bias does that automatically (spike-proven).
        let prompt = SDXLModelCatalog.Variant.fluxKlein.defaultPrompt
        XCTAssertFalse(prompt.contains("thick black outline"),
                       "Klein doesn't need outline-spelling; bias does it")
        XCTAssertFalse(prompt.contains("vector style"),
                       "Klein doesn't need vector-style spelling")
        XCTAssertTrue(prompt.lowercased().contains("coloring book"),
                      "Subject still mentions coloring book to anchor category")
    }

    func test_fluxKlein_defaultNegativePromptEmpty() {
        // Klein 4B default guidance scale is 1.0 — at scale 1.0 the
        // pipeline doesn't run classifier-free guidance, so negative prompts
        // are ignored. Empty default makes that contract explicit; user can
        // still type one (no-op until guidance > 1.0).
        XCTAssertEqual(SDXLModelCatalog.Variant.fluxKlein.defaultNegativePrompt, "")
    }

    func test_engineKind_allCasesDistinct() {
        // Future-proof: when adding a third EngineKind (e.g. .mlxFlux2,
        // .coreMLSD3), don't accidentally collide raw values.
        let raws = EngineKind.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count)
        XCTAssertEqual(EngineKind.allCases.count, 2,
                       "Phase A.4 ships 2 engine kinds; bump assertion when adding more")
    }
}
