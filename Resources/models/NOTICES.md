# Bundled Model Attribution & Licensing

Genesis Imaging Faz 2 ships pre-converted Core ML models for on-device upscale.
This document attributes the upstream model authors and licenses each bundled artifact.

---

## RealESRGAN_x4plus (Core ML)

**Bundled file:** `Resources/models/RealESRGAN_x4plus.mlmodel`

### Provenance Chain

1. **Original model architecture:** Real-ESRGAN by Xintao Wang, Liangbin Xie, Chao Dong, Ying Shan (Tencent ARC Lab, 2021).
   - Repo: <https://github.com/xinntao/Real-ESRGAN>
   - Paper: *Real-ESRGAN: Training Real-World Blind Super-Resolution with Pure Synthetic Data*, ICCV 2021 Workshops.
   - License: **BSD 3-Clause License** ([LICENSE](https://github.com/xinntao/Real-ESRGAN/blob/master/LICENSE))

2. **Trained PyTorch checkpoint:** `RealESRGAN_x4plus.pth` (~64 MB, FP32) — released by upstream authors at
   <https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth>.

3. **Core ML conversion:** Performed by community contributor `mszpro` and published to HuggingFace at
   <https://huggingface.co/mszpro/CoreML_RealESRGAN> (2023-06-27).
   - Conversion tool: `coremltools` (likely v5-7) to neuralNetwork v4 specification.
   - Fixed input: 512×512 RGB image; fixed output: 2048×2048 RGB image (4× upscale).
   - Bundled .mlmodel file size: ~64 MB (FP32 weights).

4. **Genesis Imaging integration:** Downloaded the upstream `.mlmodel.zip` (62 MB) from HuggingFace LFS,
   verified integrity via empirical predict + size match, and bundled the unzipped `.mlmodel` into the .app.
   Step 5 (release prep) will optionally INT8-quantize this model down to ~16 MB before final release packaging.

### License Application

Per the Real-ESRGAN BSD 3-Clause License:
- Redistribution permitted in source and binary forms.
- Copyright notice must be preserved.
- Original authors not used to endorse derived products without prior written permission.

Genesis Imaging redistributes the .mlmodel as part of a macOS application bundle and does not modify the
trained weights. The original copyright is reproduced in full at the bottom of this document.

### HuggingFace Repository Notice

The intermediate Core ML conversion published by `mszpro` at
`huggingface.co/mszpro/CoreML_RealESRGAN` does not include an explicit LICENSE file in the repo (verified
2026-05-11). The Real-ESRGAN BSD 3-Clause License governs the underlying weights and architecture, so
that license is applied conservatively to the bundled artifact. A courtesy attribution email to `mszpro` is
on the project follow-up backlog (cf. plan §5 release prep checklist).

---

## Original Real-ESRGAN BSD 3-Clause License

```
BSD 3-Clause License

Copyright (c) 2021, Xintao Wang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

## ncnn Models (Faz 1)

Existing Faz 1 ncnn models (`Resources/bin/models/realesrgan-*.bin` + `.param` pairs) are sourced from
the same upstream `xinntao/Real-ESRGAN` v0.2.5.0 release and governed by the same BSD 3-Clause License above.

---

## Follow-Up Actions (backlog)

1. Courtesy attribution email to `mszpro@huggingface.co` (or HF community message) — confirm Core ML
   conversion redistribution is acceptable; offer credit in app About panel.
2. Step 5 release prep: verify NOTICES.md is bundled inside .app at `Contents/Resources/NOTICES.md`
   (via `package-app.sh`).
3. App "About" panel: surface NOTICES content via "Acknowledgements" link.

---

*Genesis Imaging — Software-As-An-AI/genesis-imaging*
*Last updated: 2026-05-11*
