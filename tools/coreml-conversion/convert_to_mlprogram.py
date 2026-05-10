"""Attempt to convert legacy neuralNetwork .mlmodel → mlProgram .mlpackage.

If successful, ANE eligibility goes from LIMITED to ELIGIBLE/RISKY (mlProgram-only delegation).
"""
import sys
import time
from pathlib import Path
import coremltools as ct

src = Path("hf-model/RealESRGAN.mlmodel")
dst = Path("RealESRGAN_x4plus_mlprogram.mlpackage")

print(f"Loading {src}...", file=sys.stderr)
model = ct.models.MLModel(str(src))
spec = model.get_spec()
print(f"  source spec: {spec.WhichOneof('Type')} v{spec.specificationVersion}", file=sys.stderr)

# coremltools 8.1 supports converting nn → mlprogram via ct.convert with passed model
# Try the convert_neural_network_to_ml_program approach
try:
    # Modern API: ct.convert(model_or_spec, convert_to="mlprogram")
    print("Attempting ct.convert(spec, convert_to='mlprogram')...", file=sys.stderr)
    start = time.perf_counter()
    mlpkg = ct.convert(
        spec,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    elapsed = time.perf_counter() - start
    print(f"  converted in {elapsed:.1f}s", file=sys.stderr)
    mlpkg.save(str(dst))
    print(f"  saved {dst} ({dst.stat().st_size / (1024*1024):.1f} MB)", file=sys.stderr)
    print("OK")
except Exception as e:
    print(f"FAIL: {type(e).__name__}: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
