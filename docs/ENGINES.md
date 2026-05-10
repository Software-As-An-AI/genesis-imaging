# Engines

## Faz 1 — NcnnEngine (subprocess wrapper)

**Status:** In development (Step 4 — `Sources/NcnnEngine/`)

### How it works
1. `Resources/bin/realesrgan-ncnn-vulkan` invoked via `Process()`
2. CLI args: `-i input -o output -n model -s scale -t tileSize -m models/`
3. stderr captured → `ProgressParser` extracts `12.50%` style lines → emits `UpscaleProgress.percentage`
4. Exit 0 → `UpscaleResult` with timing + bytes; non-zero → `UpscaleError.engineFailure`
5. Cancellation: consumer task cancel → `Process.interrupt()` (SIGINT) → 3 s grace → `terminate()` (SIGTERM)

### Binary
- **Source:** [xinntao/Real-ESRGAN-ncnn-vulkan v0.2.0](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases) (April 2022, stable)
- **Architecture:** macOS arm64 / universal2 (binary release ZIP)
- **License:** BSD-3 (code) + sentetik training data (commercial OK)
- **Runtime stack:** C++ → Vulkan → MoltenVK → Metal (no Apple Neural Engine)
- **Fetch:** `scripts/fetch-ncnn-binary.sh` (gitignored — binary not committed)

### Bundled models (in `Resources/bin/models/`)
| Model | Scale | Use case |
|---|---|---|
| `realesrgan-x4plus` | 4× | General photo (default) |
| `realesrgan-x4plus-anime` | 4× | Anime / 2D art |
| `realesr-animevideov3` | 4× | Anime video frames |
| `realesrnet-x4plus` | 4× | Less aggressive denoising variant |

### Performance (M3 Pro estimate, 1024×1024 → 4096×4096)
- 6–15 s per image (tile size 0 = auto)
- M4 expected ~25–40 % faster

### Known caveats
- **MoltenVK statically linked** — large image OOM possible on tight memory (use tile size > 0 to chunk)
- **No fp16 / int8** — full f32 compute
- **No ANE** — pure GPU compute (Metal via Vulkan translation)

---

## Faz 2 — CoreMLEngine (planned)

**Status:** Stub only (`Sources/CoreMLEngine/CoreMLEngine.swift`). `init` throws `.notImplemented`. Real implementation tracked in `docs/plans/enumerated-herding-scroll.md` §8.

### Planned approach
1. Convert `RealESRGAN_x4plus.pth` PyTorch weights → `.mlpackage` via `coremltools` 8+
2. Reference: [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models) Real-ESRGAN sample
3. INT8 quantize → ~16 MB bundle (vs 64 MB FP32)
4. `MLModelConfiguration.computeUnits = .all` → ANE delegation requested (not guaranteed)
5. Tile manually via `ImagingCore/TileSplitter` (Core ML expects fixed input shape)
6. Pixel buffer ↔ CGImage conversion via `vImage` (Accelerate framework)

### Expected benefit
- M3 Pro: 3–6 s per image (vs 6–15 s ncnn)
- M4 Max: 2–4 s per image
- Lower memory pressure (no MoltenVK overhead)
- Lower power draw (ANE more efficient than GPU compute)

### Risks (tracked in plan §12)
- ANE delegation not guaranteed — Core ML may silently fall back to GPU
- Conversion may lose accuracy at INT8
- Faz 2 Step 3 (A/B benchmark) is the go/no-go gate — if no meaningful win, Faz 2 stays opt-in feature flag, ncnn remains default
