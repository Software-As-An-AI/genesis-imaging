"""Step 0 Spike — ANE compatibility inspection of pre-converted Real-ESRGAN models.

Goal: Decide whether Step 1 (PyTorch → coremltools conversion) can be skipped or
must run with informed knowledge of which ops break ANE delegation.

Output: machine-readable JSON to stdout (for SPIKE_REPORT.md generation).
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np

# Op classification — ANE-friendly, ANE-limited, ANE-incompatible.
# Source: Apple Core ML docs + community empirical reports.
ANE_FRIENDLY_OPS = {
    "Conv2D", "conv", "convolution",
    "ReLU", "relu", "leakyRelu", "prelu",
    "BatchNormalization", "batchNorm",
    "Add", "add", "Sub", "sub", "Mul", "mul",
    "MaxPool", "maxPool", "AvgPool", "avgPool", "pool",
    "Concat", "concat",
    "Upsample", "upsample", "resize_bilinear", "resize_nearest_neighbor",
    "Reshape", "reshape", "Permute", "permute", "transpose",
    "Pad", "pad",
}

ANE_LIMITED_OPS = {
    # These work on ANE but may fall back to GPU/CPU for certain shapes.
    "PixelShuffle", "pixel_shuffle", "depth_to_space",
    "GroupNorm", "group_norm",
    "Sigmoid", "sigmoid", "Tanh", "tanh",
}

ANE_INCOMPATIBLE_OPS = {
    # Known ANE-breakers — force GPU/CPU fallback.
    "GridSample", "grid_sample",
    "Einsum", "einsum",
    "FFT", "fft",
    "RNN", "LSTM", "GRU",
    "TopK", "top_k",
    "NonMaxSuppression", "nms",
}


def classify_op(op_type: str) -> str:
    """Return one of: friendly, limited, incompatible, unknown."""
    if op_type in ANE_FRIENDLY_OPS:
        return "friendly"
    if op_type in ANE_LIMITED_OPS:
        return "limited"
    if op_type in ANE_INCOMPATIBLE_OPS:
        return "incompatible"
    # Heuristic case-insensitive fallback
    lower = op_type.lower()
    for friendly in ANE_FRIENDLY_OPS:
        if friendly.lower() == lower:
            return "friendly"
    for limited in ANE_LIMITED_OPS:
        if limited.lower() == lower:
            return "limited"
    for incompat in ANE_INCOMPATIBLE_OPS:
        if incompat.lower() == lower:
            return "incompatible"
    return "unknown"


def inspect_spec(spec: Any) -> dict[str, Any]:
    """Pull format + I/O + op list from MLModel spec proto."""
    spec_type = spec.WhichOneof("Type")
    report: dict[str, Any] = {
        "spec_type": spec_type,
        "is_mlprogram": spec_type == "mlProgram",
        "spec_version": spec.specificationVersion,
        "inputs": [],
        "outputs": [],
        "ops": {},
        "ops_classification": {"friendly": 0, "limited": 0, "incompatible": 0, "unknown": 0},
    }

    for inp in spec.description.input:
        t = inp.type
        kind = t.WhichOneof("Type")
        shape_info = "unknown"
        if kind == "imageType":
            img = t.imageType
            shape_info = f"image {img.width}x{img.height} color={img.colorSpace}"
        elif kind == "multiArrayType":
            arr = t.multiArrayType
            shape_info = f"array shape={list(arr.shape)} dtype={arr.dataType}"
        report["inputs"].append({"name": inp.name, "type": kind, "info": shape_info})

    for out in spec.description.output:
        t = out.type
        kind = t.WhichOneof("Type")
        shape_info = "unknown"
        if kind == "imageType":
            img = t.imageType
            shape_info = f"image {img.width}x{img.height} color={img.colorSpace}"
        elif kind == "multiArrayType":
            arr = t.multiArrayType
            shape_info = f"array shape={list(arr.shape)} dtype={arr.dataType}"
        report["outputs"].append({"name": out.name, "type": kind, "info": shape_info})

    # Op extraction differs by spec type
    op_counts: dict[str, int] = {}
    if spec_type == "mlProgram":
        program = spec.mlProgram
        for func in program.functions.values():
            for block_spec in func.block_specializations.values():
                for op in block_spec.operations:
                    op_counts[op.type] = op_counts.get(op.type, 0) + 1
    elif spec_type == "neuralNetwork":
        nn = spec.neuralNetwork
        for layer in nn.layers:
            kind = layer.WhichOneof("layer")
            if kind:
                op_counts[kind] = op_counts.get(kind, 0) + 1
    elif spec_type == "neuralNetworkClassifier":
        nn = spec.neuralNetworkClassifier
        for layer in nn.layers:
            kind = layer.WhichOneof("layer")
            if kind:
                op_counts[kind] = op_counts.get(kind, 0) + 1

    report["ops"] = op_counts

    # Classify
    for op_type, count in op_counts.items():
        cls = classify_op(op_type)
        report["ops_classification"][cls] += count

    return report


def predict_smoke(model: ct.models.MLModel, spec_report: dict[str, Any]) -> dict[str, Any]:
    """Run a small prediction to verify the model works + measure latency."""
    smoke: dict[str, Any] = {"attempted": False, "ok": False, "latency_ms": None, "error": None}

    if not spec_report["inputs"]:
        smoke["error"] = "no input description"
        return smoke

    first_input = spec_report["inputs"][0]
    input_name = first_input["name"]
    smoke["attempted"] = True

    try:
        # Build dummy input matching the declared type
        if first_input["type"] == "imageType":
            # Generate a small PIL image. Many CoreML image models accept arbitrary input shapes.
            try:
                from PIL import Image
            except ImportError:
                smoke["error"] = "PIL not installed for imageType predict"
                return smoke
            # Parse declared shape if available
            info = first_input["info"]
            w, h = 64, 64
            try:
                parts = info.replace("image ", "").split(" ")[0]
                w, h = int(parts.split("x")[0]), int(parts.split("x")[1])
                if w == 0:
                    w = 64
                if h == 0:
                    h = 64
            except Exception:
                pass
            dummy = Image.new("RGB", (w, h), color=(128, 128, 128))
            inputs = {input_name: dummy}
        elif first_input["type"] == "multiArrayType":
            # Parse shape — fallback to (1, 3, 64, 64) NCHW
            info = first_input["info"]
            shape: list[int] = []
            try:
                import re
                m = re.search(r"shape=\[([^\]]+)\]", info)
                if m:
                    shape = [int(x.strip()) for x in m.group(1).split(",")]
            except Exception:
                pass
            if not shape:
                shape = [1, 3, 64, 64]
            # Replace any 0 dims with 64
            shape = [d if d > 0 else 64 for d in shape]
            dummy = np.random.rand(*shape).astype(np.float32)
            inputs = {input_name: dummy}
        else:
            smoke["error"] = f"unsupported input type {first_input['type']}"
            return smoke

        # Predict
        start = time.perf_counter()
        _ = model.predict(inputs)
        smoke["latency_ms"] = round((time.perf_counter() - start) * 1000, 2)
        smoke["ok"] = True
    except Exception as e:
        smoke["error"] = f"{type(e).__name__}: {e}"

    return smoke


def inspect_model(path: Path) -> dict[str, Any]:
    """Full inspection: load + spec + smoke predict."""
    report: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        report["error"] = "file not found"
        return report

    report["size_mb"] = round(path.stat().st_size / (1024 * 1024), 2)

    # Try loading with .all compute units (ANE preferred)
    try:
        config = ct.ComputeUnit.ALL
        model = ct.models.MLModel(str(path), compute_units=config)
    except Exception as e:
        report["load_error"] = f"{type(e).__name__}: {e}"
        return report

    spec = model.get_spec()
    spec_report = inspect_spec(spec)
    report.update(spec_report)

    # Smoke predict
    report["smoke"] = predict_smoke(model, spec_report)

    # ANE eligibility scoring
    total_ops = sum(spec_report["ops_classification"].values())
    if total_ops > 0:
        ane_friendly_ratio = spec_report["ops_classification"]["friendly"] / total_ops
        ane_incompat_count = spec_report["ops_classification"]["incompatible"]
        report["ane_score"] = {
            "friendly_ratio": round(ane_friendly_ratio, 3),
            "incompatible_op_count": ane_incompat_count,
            "verdict": (
                "ELIGIBLE" if (ane_incompat_count == 0 and ane_friendly_ratio > 0.6 and spec_report["is_mlprogram"])
                else "RISKY" if (ane_incompat_count == 0 and spec_report["is_mlprogram"])
                else "LIMITED" if (ane_incompat_count == 0)
                else "BLOCKED"
            ),
        }
    else:
        report["ane_score"] = {"verdict": "NO_OPS_DETECTED"}

    return report


def main() -> int:
    candidates = [
        Path("/Users/okan.yucel/Desktop/genesis-imaging/tools/coreml-conversion/hf-model/RealESRGAN.mlmodel"),
    ]

    results: list[dict[str, Any]] = []
    for path in candidates:
        print(f"\n=== Inspecting {path.name} ===", file=sys.stderr)
        result = inspect_model(path)
        results.append(result)
        # Brief stderr summary
        if "ane_score" in result:
            verdict = result["ane_score"].get("verdict", "?")
            print(f"  verdict: {verdict}", file=sys.stderr)
            print(f"  spec: {result.get('spec_type', '?')}", file=sys.stderr)
            print(f"  ops: {dict(list(result.get('ops', {}).items())[:8])}", file=sys.stderr)
        else:
            print(f"  error: {result.get('error') or result.get('load_error')}", file=sys.stderr)

    # JSON to stdout
    print(json.dumps(results, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
