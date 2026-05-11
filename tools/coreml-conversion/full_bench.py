"""Step 3 formal benchmark — ncnn-vulkan vs Core ML across multiple fixtures.

Outputs:
  - tools/coreml-conversion/bench_results.json (raw)
  - docs/BENCHMARKS.md (operator-readable markdown table)
  - tools/coreml-conversion/bench-outputs/ (PNG samples for visual review)

Metrics per (fixture, engine, run):
  - Latency (s)
  - Output dimensions
  - Cross-engine SSIM/PSNR (ncnn vs Core ML agreement)
  - Self-quality SSIM/PSNR (output downscaled 4× vs original, info preservation)
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np
from PIL import Image
from skimage.metrics import structural_similarity as ssim
from skimage.metrics import peak_signal_noise_ratio as psnr

ROOT = Path(__file__).resolve().parent
GENESIS_IMAGING_ROOT = ROOT.parent.parent
FIXTURES_DIR = ROOT / "bench-fixtures"
OUTPUTS_DIR = ROOT / "bench-outputs"
HF_MODEL = ROOT / "hf-model" / "RealESRGAN.mlmodel"
NCNN_BIN = GENESIS_IMAGING_ROOT / "Resources" / "bin" / "realesrgan-ncnn-vulkan"
NCNN_MODELS_DIR = GENESIS_IMAGING_ROOT / "Resources" / "bin" / "models"

N_RUNS = 3
WARMUP_RUNS = 1


@dataclass
class FixtureSpec:
    name: str
    width: int
    height: int
    content: str  # "gradient" | "sinusoidal-photo" | "high-freq-text"


@dataclass
class EngineResult:
    runs_s: list[float]
    min_s: float
    mean_s: float
    output_path: str
    output_width: int
    output_height: int
    output_size_mb: float


@dataclass
class FixtureBenchResult:
    fixture: FixtureSpec
    ncnn: EngineResult | dict
    coreml: EngineResult | dict
    cross_engine_ssim: float | None      # ncnn vs coreml output agreement
    cross_engine_psnr: float | None
    coreml_self_ssim: float | None       # coreml-output→downscaled vs original
    coreml_self_psnr: float | None


# ── Fixture generation ──────────────────────────────────────────────────────

def generate_gradient(size: int, seed: int = 42) -> Image.Image:
    """Color gradient + seeded noise. Tests basic upscaling."""
    arr = np.zeros((size, size, 3), dtype=np.uint8)
    for y in range(size):
        for x in range(size):
            arr[y, x, 0] = (x * 255 // size)
            arr[y, x, 1] = (y * 255 // size)
            arr[y, x, 2] = ((x + y) * 127 // size) % 256
    rng = np.random.default_rng(seed=seed)
    noise = rng.integers(-20, 20, size=(size, size, 3), dtype=np.int32)
    return Image.fromarray(np.clip(arr.astype(np.int32) + noise, 0, 255).astype(np.uint8), mode="RGB")


def generate_sinusoidal_photo(size: int) -> Image.Image:
    """Photo-like sinusoidal patterns at multiple frequencies.
    Approximates natural image distribution (low + mid + high frequency mix)."""
    x = np.linspace(0, 2 * np.pi, size)
    y = np.linspace(0, 2 * np.pi, size)
    xx, yy = np.meshgrid(x, y)

    r = (np.sin(xx * 4) * 0.3 + np.sin(yy * 6) * 0.2 + np.sin((xx + yy) * 10) * 0.1 + 0.5) * 255
    g = (np.sin(yy * 3) * 0.3 + np.cos(xx * 5) * 0.2 + np.sin(xx * yy * 0.5) * 0.1 + 0.5) * 255
    b = (np.cos(xx * 2) * 0.3 + np.sin(yy * 7) * 0.2 + np.cos((xx - yy) * 8) * 0.1 + 0.5) * 255

    rng = np.random.default_rng(seed=7)
    noise = rng.integers(-5, 5, size=(size, size, 3), dtype=np.int32)

    arr = np.stack([r, g, b], axis=-1)
    arr = np.clip(arr.astype(np.int32) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode="RGB")


def generate_high_freq_text(size: int) -> Image.Image:
    """High-frequency black/white stripes + text-like rectangles.
    Tests engine's handling of sharp edges + thin strokes."""
    arr = np.full((size, size, 3), 240, dtype=np.uint8)  # near-white background

    # Horizontal stripes (very thin — 1 px each, alternating)
    for y in range(0, size, 4):
        if y % 8 == 0:
            arr[y:y+1, :, :] = 30

    # Vertical stripes
    for x in range(size // 4, size // 2, 6):
        arr[:, x:x+2, :] = 60

    # Text-like rectangles (simulated glyphs)
    for row in range(size // 3, size * 2 // 3, 24):
        for col in range(size // 8, size * 7 // 8, 32):
            arr[row:row+12, col:col+18, :] = 20

    return Image.fromarray(arr, mode="RGB")


def ensure_fixtures(fixtures: list[FixtureSpec]) -> dict[str, Path]:
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for spec in fixtures:
        out = FIXTURES_DIR / f"{spec.name}.png"
        if not out.exists():
            print(f"[fixture] generating {spec.name} ({spec.width}x{spec.height} {spec.content})", file=sys.stderr)
            if spec.content == "gradient":
                img = generate_gradient(spec.width)
            elif spec.content == "sinusoidal-photo":
                img = generate_sinusoidal_photo(spec.width)
            elif spec.content == "high-freq-text":
                img = generate_high_freq_text(spec.width)
            else:
                raise ValueError(f"unknown content type: {spec.content}")
            img.save(out)
        paths[spec.name] = out
    return paths


# ── Engine runners ──────────────────────────────────────────────────────────

def bench_ncnn(fixture: Path, output: Path) -> EngineResult | dict:
    if not NCNN_BIN.exists():
        return {"error": f"ncnn binary not found: {NCNN_BIN}"}

    cmd = [
        str(NCNN_BIN),
        "-i", str(fixture),
        "-o", str(output),
        "-n", "realesrgan-x4plus",
        "-s", "4",
        "-m", str(NCNN_MODELS_DIR),
    ]

    # Warm-up
    for _ in range(WARMUP_RUNS):
        subprocess.run(cmd, capture_output=True, check=False)

    # Timed
    times = []
    for i in range(N_RUNS):
        start = time.perf_counter()
        result = subprocess.run(cmd, capture_output=True, check=False)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        if not output.exists() or output.stat().st_size == 0:
            return {"error": f"ncnn run {i+1} produced no output: stderr={result.stderr.decode()[:200]}"}

    img = Image.open(output)
    return EngineResult(
        runs_s=[round(t, 3) for t in times],
        min_s=round(min(times), 3),
        mean_s=round(sum(times) / len(times), 3),
        output_path=str(output),
        output_width=img.size[0],
        output_height=img.size[1],
        output_size_mb=round(output.stat().st_size / (1024 * 1024), 2),
    )


def bench_coreml(model: ct.models.MLModel, fixture: Path, output: Path) -> EngineResult | dict:
    """Predict using coremltools loaded model. For images larger than 512×512
    we split into tiles like CoreMLEngine.swift does."""
    if not HF_MODEL.exists():
        return {"error": f"HF model not found: {HF_MODEL}"}

    src = Image.open(fixture).convert("RGB")
    w, h = src.size
    tile_size = 512
    scale = 4

    cols = max(1, (w + tile_size - 1) // tile_size)
    rows = max(1, (h + tile_size - 1) // tile_size)
    total_tiles = cols * rows

    output_w, output_h = w * scale, h * scale

    times = []
    # Warm-up — single predict
    if WARMUP_RUNS > 0:
        warmup_tile = Image.new("RGB", (tile_size, tile_size), (128, 128, 128))
        _ = model.predict({"input": warmup_tile})

    # Tile-based upscale × N runs
    for run_idx in range(N_RUNS):
        canvas = Image.new("RGB", (output_w, output_h), (0, 0, 0))
        start = time.perf_counter()
        for r in range(rows):
            for c in range(cols):
                ox, oy = c * tile_size, r * tile_size
                content_w = min(tile_size, w - ox)
                content_h = min(tile_size, h - oy)

                # Build tile input (pad with black if edge)
                tile_in = Image.new("RGB", (tile_size, tile_size), (0, 0, 0))
                crop = src.crop((ox, oy, ox + content_w, oy + content_h))
                tile_in.paste(crop, (0, 0))

                # Predict
                out_dict = model.predict({"input": tile_in})
                tile_out = next(v for v in out_dict.values() if isinstance(v, Image.Image))

                # Paste content region into canvas (drop padded margin)
                paste_box = (ox * scale, oy * scale,
                             ox * scale + content_w * scale, oy * scale + content_h * scale)
                content_out = tile_out.crop((0, 0, content_w * scale, content_h * scale))
                canvas.paste(content_out, paste_box)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        if run_idx == 0:
            canvas.save(output)

    return EngineResult(
        runs_s=[round(t, 3) for t in times],
        min_s=round(min(times), 3),
        mean_s=round(sum(times) / len(times), 3),
        output_path=str(output),
        output_width=output_w,
        output_height=output_h,
        output_size_mb=round(output.stat().st_size / (1024 * 1024), 2),
    )


# ── Quality metrics ─────────────────────────────────────────────────────────

def to_array(img: Image.Image) -> np.ndarray:
    return np.array(img.convert("RGB"))


def cross_engine_metrics(ncnn_out: Path, coreml_out: Path) -> tuple[float | None, float | None]:
    """How much do the two engines agree? Higher SSIM = similar quality."""
    a = to_array(Image.open(ncnn_out))
    b = to_array(Image.open(coreml_out))
    if a.shape != b.shape:
        return None, None
    s = float(ssim(a, b, channel_axis=2, data_range=255))
    p = float(psnr(a, b, data_range=255))
    return s, p


def self_quality_metrics(original: Path, upscaled: Path, scale: int = 4) -> tuple[float | None, float | None]:
    """Does the upscale preserve original info? Downscale output by `scale`
    and compare to the original. Higher SSIM = better info preservation."""
    orig = Image.open(original).convert("RGB")
    ups = Image.open(upscaled).convert("RGB")
    if ups.size[0] != orig.size[0] * scale:
        return None, None
    downscaled = ups.resize(orig.size, Image.LANCZOS)
    a = to_array(orig)
    b = to_array(downscaled)
    s = float(ssim(a, b, channel_axis=2, data_range=255))
    p = float(psnr(a, b, data_range=255))
    return s, p


# ── Main orchestration ──────────────────────────────────────────────────────

def main() -> int:
    fixtures = [
        FixtureSpec(name="small-gradient-256",       width=256,  height=256,  content="gradient"),
        FixtureSpec(name="medium-gradient-512",      width=512,  height=512,  content="gradient"),
        FixtureSpec(name="large-gradient-1024",      width=1024, height=1024, content="gradient"),
        FixtureSpec(name="photo-sinusoidal-512",     width=512,  height=512,  content="sinusoidal-photo"),
        FixtureSpec(name="text-high-frequency-512",  width=512,  height=512,  content="high-freq-text"),
    ]

    fixture_paths = ensure_fixtures(fixtures)
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"[bench] loading Core ML model from {HF_MODEL.name}...", file=sys.stderr)
    model = ct.models.MLModel(str(HF_MODEL), compute_units=ct.ComputeUnit.ALL)

    results: list[FixtureBenchResult] = []
    for spec in fixtures:
        print(f"\n=== Fixture: {spec.name} ({spec.width}x{spec.height}) ===", file=sys.stderr)
        fixture = fixture_paths[spec.name]
        ncnn_out = OUTPUTS_DIR / f"{spec.name}-ncnn.png"
        coreml_out = OUTPUTS_DIR / f"{spec.name}-coreml.png"

        print(f"  ncnn-vulkan...", file=sys.stderr)
        ncnn_result = bench_ncnn(fixture, ncnn_out)
        if isinstance(ncnn_result, EngineResult):
            print(f"    mean {ncnn_result.mean_s}s · output {ncnn_result.output_width}x{ncnn_result.output_height}", file=sys.stderr)
        else:
            print(f"    ERROR: {ncnn_result}", file=sys.stderr)

        print(f"  core-ml...", file=sys.stderr)
        coreml_result = bench_coreml(model, fixture, coreml_out)
        if isinstance(coreml_result, EngineResult):
            print(f"    mean {coreml_result.mean_s}s · output {coreml_result.output_width}x{coreml_result.output_height}", file=sys.stderr)
        else:
            print(f"    ERROR: {coreml_result}", file=sys.stderr)

        # Quality metrics
        cross_ssim: float | None = None
        cross_psnr: float | None = None
        coreml_self_ssim: float | None = None
        coreml_self_psnr: float | None = None
        if isinstance(ncnn_result, EngineResult) and isinstance(coreml_result, EngineResult):
            try:
                cross_ssim, cross_psnr = cross_engine_metrics(ncnn_out, coreml_out)
                print(f"  cross-engine: SSIM={cross_ssim:.4f} PSNR={cross_psnr:.2f} dB", file=sys.stderr)
            except Exception as e:
                print(f"  cross-engine metric FAIL: {e}", file=sys.stderr)
        if isinstance(coreml_result, EngineResult):
            try:
                coreml_self_ssim, coreml_self_psnr = self_quality_metrics(fixture, coreml_out, scale=4)
                print(f"  coreml self: SSIM={coreml_self_ssim:.4f} PSNR={coreml_self_psnr:.2f} dB", file=sys.stderr)
            except Exception as e:
                print(f"  coreml self metric FAIL: {e}", file=sys.stderr)

        results.append(FixtureBenchResult(
            fixture=spec,
            ncnn=ncnn_result if isinstance(ncnn_result, EngineResult) else ncnn_result,
            coreml=coreml_result if isinstance(coreml_result, EngineResult) else coreml_result,
            cross_engine_ssim=cross_ssim,
            cross_engine_psnr=cross_psnr,
            coreml_self_ssim=coreml_self_ssim,
            coreml_self_psnr=coreml_self_psnr,
        ))

    # JSON dump
    raw = []
    for r in results:
        raw.append({
            "fixture": asdict(r.fixture),
            "ncnn": asdict(r.ncnn) if isinstance(r.ncnn, EngineResult) else r.ncnn,
            "coreml": asdict(r.coreml) if isinstance(r.coreml, EngineResult) else r.coreml,
            "cross_engine_ssim": r.cross_engine_ssim,
            "cross_engine_psnr": r.cross_engine_psnr,
            "coreml_self_ssim": r.coreml_self_ssim,
            "coreml_self_psnr": r.coreml_self_psnr,
        })
    (ROOT / "bench_results.json").write_text(json.dumps(raw, indent=2, default=str))
    print(f"\n[bench] wrote {ROOT}/bench_results.json", file=sys.stderr)
    print(json.dumps(raw, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
