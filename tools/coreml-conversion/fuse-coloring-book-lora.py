#!/usr/bin/env python
"""tools/coreml-conversion/fuse-coloring-book-lora.py

Phase A.3 Step 1 — fuse ColoringBookRedmond-V2 LoRA into SDXL base, save the
merged checkpoint as a diffusers directory ready for Step 2 (torch2coreml).

Inputs:
    - HF: stabilityai/stable-diffusion-xl-base-1.0 (FP16, ~14 GB first download)
    - HF: artificialguybr/ColoringBookRedmond-V2 (LoRA, ~600 MB)

Output:
    - ./sdxl-coloring-book-fused/  (~14 GB diffusers checkpoint)

Wall time: 5-15 min cached / 20-40 min cold (SDXL FP16 download dominates).

Sanity checks:
    1. UNet down_block weight tensor changes vs pre-fuse (catches silent no-op).
    2. Output dir contains expected diffusers subdirs.

Run:
    source .venv-lora/bin/activate
    cd tools/coreml-conversion
    ./fuse-coloring-book-lora.py

Reference: docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md §Step 1
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import torch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("fuse-lora")

BASE_MODEL = "stabilityai/stable-diffusion-xl-base-1.0"
LORA_MODEL = "artificialguybr/ColoringBookRedmond-V2"
LORA_WEIGHT_NAME = "ColoringBookRedmond-ColoringBook-ColoringBookAF.safetensors"
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "sdxl-coloring-book-fused"
DEFAULT_LORA_SCALE = 1.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    ap.add_argument("--lora-scale", type=float, default=DEFAULT_LORA_SCALE)
    ap.add_argument(
        "--lora-weight-name",
        default=LORA_WEIGHT_NAME,
        help=(
            "Explicit LoRA file name in repo. Default: "
            f"{LORA_WEIGHT_NAME} (discovered via huggingface_hub list_repo_files)."
        ),
    )
    args = ap.parse_args()

    if args.output.exists():
        log.warning("Output %s exists — will overwrite contents", args.output)

    log.info("Loading SDXL base (FP16): %s", BASE_MODEL)
    log.info("  cache: %s", Path.home() / ".cache/huggingface/hub")
    t0 = time.perf_counter()

    from diffusers import StableDiffusionXLPipeline

    pipeline = StableDiffusionXLPipeline.from_pretrained(
        BASE_MODEL,
        torch_dtype=torch.float16,
        use_safetensors=True,
        variant="fp16",
    )
    log.info("  loaded in %.1fs", time.perf_counter() - t0)

    # Sanity snapshot: a UNet attention weight that LoRAs typically patch.
    # ResNet conv weights are NOT touched by most LoRAs — must sample from
    # to_q/to_k/to_v/to_out projections in transformer attention blocks.
    # SDXL down_blocks[1] is the first block with attentions (block 0 is
    # pure ResNet downsample without transformer).
    sample_param = (
        pipeline.unet.down_blocks[1]
        .attentions[0]
        .transformer_blocks[0]
        .attn1.to_q.weight
    )
    pre_fuse_norm = sample_param.detach().float().norm().item()
    log.info("  pre-fuse UNet attn.to_q sample weight norm: %.6f", pre_fuse_norm)

    log.info("Loading LoRA weights: %s", LORA_MODEL)
    t0 = time.perf_counter()
    try:
        pipeline.load_lora_weights(LORA_MODEL, weight_name=args.lora_weight_name)
    except Exception as exc:
        log.error("load_lora_weights failed: %s", exc)
        log.error(
            "If the repo has multiple .safetensors files, rerun with "
            "--lora-weight-name <filename>"
        )
        return 1
    log.info("  loaded in %.1fs", time.perf_counter() - t0)

    log.info("Fusing LoRA into base (scale=%s)", args.lora_scale)
    t0 = time.perf_counter()
    pipeline.fuse_lora(lora_scale=args.lora_scale)
    log.info("  fused in %.1fs", time.perf_counter() - t0)

    # Sanity: same tensor after fuse — must differ.
    post_fuse_norm = sample_param.detach().float().norm().item()
    log.info("  post-fuse UNet attn.to_q sample weight norm: %.6f", post_fuse_norm)
    delta = abs(post_fuse_norm - pre_fuse_norm)
    if delta < 1e-6:
        log.error(
            "Pre/post-fuse norms identical (Δ=%.2e). LoRA fuse silently "
            "no-opped — likely wrong key matching or empty LoRA. ABORT.",
            delta,
        )
        return 2
    log.info("  ✓ fuse delta confirmed: Δ=%.6f", delta)

    log.info("Unloading LoRA refs (now baked into base weights)")
    pipeline.unload_lora_weights()

    log.info("Saving fused pipeline to %s", args.output)
    t0 = time.perf_counter()
    pipeline.save_pretrained(args.output, safe_serialization=True)
    log.info("  saved in %.1fs", time.perf_counter() - t0)

    # Output structure sanity
    expected = [
        "unet", "text_encoder", "text_encoder_2", "vae",
        "tokenizer", "tokenizer_2", "scheduler", "model_index.json",
    ]
    missing = [e for e in expected if not (args.output / e).exists()]
    if missing:
        log.error("Output missing expected subdirs/files: %s", missing)
        return 3

    size_gb = sum(
        p.stat().st_size for p in args.output.rglob("*") if p.is_file()
    ) / (1024**3)
    log.info("  ✓ output dir size: %.2f GB", size_gb)
    log.info("  ✓ structure OK: %s", expected)

    log.info("")
    log.info("Step 1 complete.")
    log.info(
        "Next: ./convert-fused-to-coreml.sh  (Step 2, ~2-3 h wall time)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
