---
created: 2026-05-11
status: DEFER
owner: null
due: null
---

# Genesis Imaging: PreflightValidator dual-directory model check (ncnn + Core ML)

**Why deferred:** `PreflightValidator.checkModelPresence` currently takes a
single `modelsDirectory: URL?` and looks for either `<dir>/<model>.bin +
.param` (ncnn) OR `<dir>/<model>.mlmodelc` (Core ML) in the SAME directory.
In practice the two engines store their models in DIFFERENT bundle paths:

- ncnn: `Bundle/Contents/Resources/bin/models/realesrgan-x4plus.{bin,param}`
- Core ML: `Bundle/Contents/Resources/Models/realesrgan-x4plus.mlmodelc`
  (or similar — verify exact path when picking this up)

Current `MainView.resolvedModelsDirectory` delegates to
`BinaryLocator.defaultModelsDirectory()` which returns the **ncnn** path
only. If a user switches Engine preference to Core ML in Settings AND the
PreflightValidator's single-dir lookup misses the Core ML path, the
"Model dosyası eksik: realesrgan-x4plus" false positive returns — blocking
the batch flow even though Core ML model is actually bundled.

**Why now-acceptable:** Faz 2 default is `.auto` engine preference which
falls back to ncnn-vulkan if Core ML model fetch fails. ncnn path resolves
correctly via BinaryLocator. So users with default settings don't hit this.
Edge case = explicit Core ML preference + alpha tester behavior.

**Pickup conditions:**
- Alpha tester report: "Settings = Core ML, batch says model missing"
- v0.3.1+ work touching `PreflightValidator.checkModelPresence` or
  `BinaryLocator`
- Adding a `CoreMLLocator.defaultModelsDirectory()` symmetric to
  `BinaryLocator` (current code doesn't have a Core ML locator separate from
  the engine init)
- Performance audit of pre-flight latency (multi-dir check is slightly
  slower)

**Implementation sketch:**
- Refactor `PreflightValidator.checkModelPresence` to accept `[URL]` list of
  candidate dirs (or two distinct params: `ncnnModelsDirectory` +
  `coremlModelsDirectory`)
- For each model name, return `nil` (pass) if ANY candidate dir contains
  the artifacts — fail only when neither finds it
- Add `CoreMLLocator.defaultModelsDirectory()` mirroring BinaryLocator
- Update `MainView.resolvedModelsDirectory` accessor → return both URLs
- Update `BatchQueue.preflight()` signature + callers
- New test fixtures: clean ncnn dir + clean coreml dir + each with
  different subsets of models

**Related work:**
- `Sources/ImagingCore/PreflightValidator.swift:188-209` (checkModelPresence)
- `Sources/NcnnEngine/BinaryLocator.swift` (canonical ncnn resolver — pattern
  to mirror for CoreML)
- `Sources/CoreMLEngine/` (likely contains current Core ML model path logic
  inline — extract into `CoreMLLocator`)
- `Sources/AppShell/Views/MainView.swift:59-61` (resolvedModelsDirectory)
- Cross-ref: commit `df5261d` (first observation — single-dir was wrong
  path entirely; this backlog handles the dual-engine extension)

**Last touched:** 2026-05-11 (S57 batch upscale smoke surfaced as v0.3+ refactor)
