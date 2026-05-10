"""Step 0 mini A/B benchmark — ncnn-vulkan vs HF Core ML (legacy neuralNetwork).

Aim: empirical answer to "is Core ML (.all compute units) faster than ncnn-vulkan
on M4 Pro for a 512×512 → 2048×2048 upscale?"

Output:
  - fixture-512.png (generated random gradient + noise)
  - out_ncnn.png, out_coreml.png
  - JSON results to stdout (ncnn vs coreml stats)
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
from PIL import Image

# Paths
ROOT = Path(__file__).resolve().parent
GENESIS_IMAGING_ROOT = ROOT.parent.parent  # ~/Desktop/genesis-imaging
FIXTURE = ROOT / "fixture-512.png"
OUT_NCNN = ROOT / "out_ncnn.png"
OUT_COREML = ROOT / "out_coreml.png"
HF_MODEL = ROOT / "hf-model" / "RealESRGAN.mlmodel"
NCNN_BIN = GENESIS_IMAGING_ROOT / "Resources" / "bin" / "realesrgan-ncnn-vulkan"
NCNN_MODELS_DIR = GENESIS_IMAGING_ROOT / "Resources" / "bin" / "models"

N_RUNS = 3
WARMUP_RUNS = 1


def generate_fixture(size: int = 512) -> Image.Image:
    """Generate a 512×512 RGB fixture: gradient + colored noise."""
    arr = np.zeros((size, size, 3), dtype=np.uint8)
    # Linear gradient
    for y in range(size):
        for x in range(size):
            arr[y, x, 0] = (x * 255 // size)
            arr[y, x, 1] = (y * 255 // size)
            arr[y, x, 2] = ((x + y) * 127 // size) % 256
    # Add Perlin-ish noise structure (visible detail to upscale)
    rng = np.random.default_rng(seed=42)
    noise = rng.integers(-20, 20, size=(size, size, 3), dtype=np.int32)
    arr = np.clip(arr.astype(np.int32) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode="RGB")


def bench_ncnn() -> dict:
    """Run ncnn-vulkan 3 times on fixture; return latency stats."""
    times = []
    cmd = [
        str(NCNN_BIN),
        "-i", str(FIXTURE),
        "-o", str(OUT_NCNN),
        "-n", "realesrgan-x4plus",
        "-s", "4",
        "-m", str(NCNN_MODELS_DIR),
    ]
    print(f"  cmd: {' '.join(cmd)}", file=sys.stderr)

    # Warm-up
    for _ in range(WARMUP_RUNS):
        subprocess.run(cmd, capture_output=True, check=False)

    # Timed runs
    for i in range(N_RUNS):
        start = time.perf_counter()
        result = subprocess.run(cmd, capture_output=True, check=False)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        if result.returncode != 0 and not OUT_NCNN.exists():
            return {"error": f"ncnn run {i+1} failed: rc={result.returncode}, stderr={result.stderr.decode()[:200]}"}
        # Check output exists + non-zero
        if not OUT_NCNN.exists() or OUT_NCNN.stat().st_size == 0:
            return {"error": f"ncnn run {i+1} produced no output"}

    return {
        "runs_s": [round(t, 3) for t in times],
        "min_s": round(min(times), 3),
        "max_s": round(max(times), 3),
        "mean_s": round(sum(times) / len(times), 3),
        "output_size_mb": round(OUT_NCNN.stat().st_size / (1024 * 1024), 2),
    }


def bench_coreml() -> dict:
    """Load HF Core ML model + predict 3 times on fixture; return latency stats."""
    print(f"  loading {HF_MODEL.name} (compute_units=ALL)...", file=sys.stderr)
    model = ct.models.MLModel(str(HF_MODEL), compute_units=ct.ComputeUnit.ALL)

    input_img = Image.open(FIXTURE).resize((512, 512))
    inputs = {"input": input_img}

    # Warm-up (first predict often includes model compilation to ANE/GPU)
    for i in range(WARMUP_RUNS):
        print(f"  warmup {i+1}/{WARMUP_RUNS}...", file=sys.stderr)
        _ = model.predict(inputs)

    # Timed runs
    times = []
    output_img: Image.Image | None = None
    for i in range(N_RUNS):
        start = time.perf_counter()
        out = model.predict(inputs)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        # First output for saving
        if i == 0:
            # Output key auto-detected from spec — for HF model: 'activation_out'
            for key, value in out.items():
                if isinstance(value, Image.Image):
                    output_img = value
                    break

    if output_img is not None:
        output_img.save(OUT_COREML)

    return {
        "runs_s": [round(t, 3) for t in times],
        "min_s": round(min(times), 3),
        "max_s": round(max(times), 3),
        "mean_s": round(sum(times) / len(times), 3),
        "output_size_mb": round(OUT_COREML.stat().st_size / (1024 * 1024), 2) if OUT_COREML.exists() else None,
        "output_dimensions": f"{output_img.width}x{output_img.height}" if output_img else None,
    }


def main() -> int:
    # Generate fixture if missing
    if not FIXTURE.exists():
        print(f"Generating fixture {FIXTURE.name}...", file=sys.stderr)
        img = generate_fixture(512)
        img.save(FIXTURE)
    print(f"Fixture: {FIXTURE.name} ({FIXTURE.stat().st_size / 1024:.1f} KB, 512x512)", file=sys.stderr)

    results = {}

    # ncnn bench
    print("\n=== Benchmarking ncnn-vulkan ===", file=sys.stderr)
    if not NCNN_BIN.exists():
        results["ncnn"] = {"error": f"ncnn binary not found: {NCNN_BIN}"}
    else:
        results["ncnn"] = bench_ncnn()
        print(f"  result: {results['ncnn']}", file=sys.stderr)

    # Core ML bench
    print("\n=== Benchmarking HF Core ML ===", file=sys.stderr)
    if not HF_MODEL.exists():
        results["coreml"] = {"error": f"HF model not found: {HF_MODEL}"}
    else:
        results["coreml"] = bench_coreml()
        print(f"  result: {results['coreml']}", file=sys.stderr)

    # Compare
    if "mean_s" in results.get("ncnn", {}) and "mean_s" in results.get("coreml", {}):
        ncnn_mean = results["ncnn"]["mean_s"]
        coreml_mean = results["coreml"]["mean_s"]
        speedup = ncnn_mean / coreml_mean if coreml_mean > 0 else None
        results["comparison"] = {
            "ncnn_mean_s": ncnn_mean,
            "coreml_mean_s": coreml_mean,
            "speedup_coreml_over_ncnn": round(speedup, 2) if speedup else None,
            "verdict": (
                "CORE_ML_FASTER" if speedup and speedup > 1.2
                else "NCNN_FASTER" if speedup and speedup < 0.8
                else "ROUGHLY_EQUAL"
            ),
        }

    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
