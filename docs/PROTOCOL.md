# UpscaleEngine Protocol — SSOT

> **Source file:** `Sources/ImagingCore/UpscaleEngineProtocol.swift`
> **Status:** Faz 1 — protocol stable, NcnnEngine implementation lands in Step 4.
> **Versioning:** Semantic. Breaking changes require bump + plan note.

## Purpose

`UpscaleEngine` is the single contract that all upscaling backends conform to. UI, ViewModels, history, and settings code knows nothing about which engine runs underneath — they call protocol methods.

This is what guarantees Faz 2 (Core ML) is a **swap, not a rewrite**: when `CoreMLEngine.init` and `.upscale` get real implementations, no caller changes.

## Conforming Types

| Type | File | Status |
|---|---|---|
| `NcnnEngine` | `Sources/NcnnEngine/NcnnEngine.swift` | Faz 1 — Step 4 in progress |
| `CoreMLEngine` | `Sources/CoreMLEngine/CoreMLEngine.swift` | Faz 1: stub throws `.notImplemented`. Faz 2: real impl. |
| `MockEngine` | `Tests/.../MockEngine.swift` | Test harness — yields scripted progress events |

## Surface

```swift
public protocol UpscaleEngine: Sendable {
    var engineName: String { get }
    var supportedModels: [String] { get }

    func supportsScale(_ scale: Int) -> Bool
    func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error>
    func probe() async throws -> EngineHealth
}
```

### Why `AsyncThrowingStream<UpscaleProgress>`

- SwiftUI `ProgressView(value:)` consumes it via `for try await`
- Cancellation is native — consumer task cancel → engine receives SIGINT (NcnnEngine) or task cancel check (CoreMLEngine)
- Single channel for both progress events and final result/error (no separate completion handler)

### Why `engineName: String` (not enum)

Future engines (e.g., MLX-based, custom Metal compute) shouldn't require a breaking enum change. Strings are read-only display labels in UI; logic decisions key on protocol type, not name.

### Why `EngineHealth.detectedDevice: String?` (Optional)

Faz 1 (`ncnn-vulkan`) can introspect Vulkan device ("Apple M4 Pro"). Faz 2 (Core ML) **cannot reliably report whether ANE was actually used** — Core ML may silently fall back to GPU. Optional reflects this honesty.

## Errors

```swift
public enum UpscaleError: Error, Sendable, Equatable {
    case binaryNotFound(path: String)        // ncnn binary missing
    case modelNotFound(name: String)         // model file missing in models/
    case unsupportedFormat(mediaType: String)
    case engineFailure(exitCode: Int32, stderr: String)
    case cancelled
    case ioError(message: String)
    case notImplemented(reason: String)      // Faz 2 placeholder
}
```

UI surfaces these via `.failed(UpscaleError)` progress event or thrown error from the stream. Each engine **maps native errors** (NSError, exit codes, stderr) to this taxonomy — UI sees only `UpscaleError`.

## Versioning

Breaking changes:
- Removing or renaming protocol methods
- Changing parameter types
- Removing enum cases

Non-breaking:
- Adding new enum cases (consumers handle `@unknown default` if needed)
- Adding optional properties
- Adding new conforming types

Any breaking change → bump major version in `genesis.json` + note in `docs/plans/`.
