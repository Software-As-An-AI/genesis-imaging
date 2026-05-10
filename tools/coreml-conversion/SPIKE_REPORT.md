# Step 0 Spike Report — ANE Compatibility + Empirical A/B

**Tarih:** 2026-05-11 ~05:20 Bangkok TZ (Faz 2 Step 0)
**Host:** Apple M4 Pro, macOS 14+
**Hedef:** Step 1 (PyTorch → Core ML conversion ~6h) körlemesine yatırımdan önce hazır `.mlpackage`/`.mlmodel`'lerle ANE compatibility + hız kanıtı topla.

---

## TL;DR

**Step 1 ATLANIR.** Hazır HuggingFace `mszpro/CoreML_RealESRGAN` modeli M4 Pro'da ncnn-vulkan'dan **5.2× daha hızlı** (0.61s vs 3.17s, 512×512 → 2048×2048). Format legacy (neuralNetwork v4) ama `compute_units=ALL` ile Apple silikon native execution path'i kullanıyor. Step 1'in ~6h'i tamamen tasarruf edildi; Step 2 (CoreMLEngine impl) modeli doğrudan tüketebilir.

---

## Candidate Models Inspected

### 1. HuggingFace `mszpro/CoreML_RealESRGAN/RealESRGAN.mlmodel.zip`

- **Source:** https://huggingface.co/mszpro/CoreML_RealESRGAN (2023-06-27, public, no LFS issues via direct curl)
- **Size:** 64 MB (FP32, unzipped from 59 MB zip)
- **Format:** `neuralNetwork` v4 (legacy — NOT mlProgram)
- **Input:** `input` image 512×512 RGB
- **Output:** `activation_out` image 2048×2048 RGB (fixed 4× upscale)
- **Ops:**
  - convolution: 351
  - activation: 280 (generic — likely ReLU/LeakyReLU)
  - concat: 276
  - add: 93
  - multiply: 23
  - upsample: 2
  - squeeze: 1
  - **Total: 1026 ops, 0 ANE-incompatible**
- **ANE eligibility (theoretical):** LIMITED — neuralNetwork format'ı mlProgram kadar agresif ANE delegation yapmaz; ama op'lar temiz.

### 2. `john-rocky/CoreML-Models` (rejected)

Real-ESRGAN README'da listelenmiş ama **pre-built model repo'da yok** (Google Drive link'leri var). Conversion script var ama Real-ESRGAN-spesifik değil. Skip.

---

## Empirical A/B Benchmark (mini)

**Setup:**
- Fixture: 512×512 RGB PNG (gradient + seeded noise, 583 KB)
- Output: 2048×2048 RGB PNG (4× upscale)
- Each engine: 1 warmup + 3 timed runs
- Same M4 Pro, no other heavy load

| Engine | Run 1 | Run 2 | Run 3 | Mean | Output |
|---|---|---|---|---|---|
| **ncnn-vulkan v0.2.5.0** (Vulkan/MoltenVK → Metal) | 3.168 s | 3.174 s | 3.168 s | **3.17 s** | 5.93 MB PNG |
| **HF Core ML** (`compute_units=ALL`, neuralNetwork v4) | 0.608 s | 0.609 s | 0.612 s | **0.61 s** | 4.39 MB PNG |

**Speedup: Core ML 5.2× faster than ncnn-vulkan.** Variance <%1 each (warm cache, identical fixture).

---

## ANE Evidence (Indirect)

- `compute_units=ALL` izin verilen tüm path'leri ANE → GPU → CPU sırasında dener
- 0.61s latency neuralNetwork model için **Metal/MPSGraph native compute** mertebesinde (Vulkan stack overhead'i yok)
- Direct ANE wattage ölçümü için `sudo powermetrics --samplers ane_power` Step 3 benchmark gateway'de yapılır
- **Yeterli kanıt mevcut: Core ML path'i ncnn'den çok hızlı, ANE delegation kısmen veya tam olabilir; her durumda kazanım empirik**

---

## Karar Matrisi

| Yol | Süre | Sonuç |
|---|---|---|
| **A — HF model'i Step 2'ye doğrudan ver** (önerilen) | 0h ek | Step 1 skip; CoreMLEngine impl HF .mlmodel'i tüketir |
| **B — Step 1 normal (PyTorch → mlProgram + INT8)** | ~6h | mlProgram format + ~16 MB INT8 bundle; ANE delegation theoretical olarak daha agresif ama empirik kanıt yok |
| **C — Hibrit: HF model ile Step 2 + Step 5'te INT8 quantize** (opsiyonel) | ~1h | Bundle 64 MB → ~16 MB; latency aynı veya marjinal değişir |

**Önerilen:** **A** — empirik kanıt 5× kazanım gösterdi, format legacy olmasına rağmen runtime sorunsuz. Step 5'te isteğe bağlı C (INT8 quantize) eklenebilir (bundle size optimization).

---

## Faz 2 Plan Revize (Step 0 sonrası)

| # | Adım | Süre | Değişiklik |
|---|---|---|---|
| Step 0 | ✓ Spike (bu rapor) | ~1.5h actual | Tamamlandı |
| ~~Step 1~~ | ~~Core ML conversion~~ | ~~6h~~ | **SKIP — HF model yeterli** |
| Step 2 | CoreMLEngine impl + TileSplitter | ~5h | HF model fixed 512×512 input — TileSplitter zorunlu |
| Step 3 | A/B Benchmark Gateway (geniş suite + ANE evidence) | ~3h | Mini-bench önümüze döndü, full suite Step 3'te |
| Step 4 | Settings Engine Selector | ~2h | Step 3 yeşil bekleniyor |
| Step 5 | v0.2.0 Release (+ opsiyonel INT8 quantize) | ~2-3h | Bundle 64 MB veya quantize sonrası ~16 MB |

**Yeni toplam:** ~12-14h (önce ~19-20h). **5-6h tasarruf, empirik kanıtlı.**

---

## Open Questions for Operator

1. **C opsiyonu (INT8 quantize Step 5'te)** dahil edilsin mi? Bundle 64MB → ~16MB, kullanıcı download süresi düşer; latency etkisi belirsiz (büyük olasılıkla aynı veya hafif artış FP32 → INT8 dequant cost).
2. **HF model lisansı** — `mszpro/CoreML_RealESRGAN` repo'da `LICENSE` yok, README sadece 1 satır. Şu an varsayım: Real-ESRGAN orijinal BSD-3-Clause lisansı geçerli (Apache 2.0 ile uyumlu). Bundle'a göme öncesi resmi onay/notice yazımı (`Resources/models/NOTICES.md`) Step 5'te zorunlu.
3. **Visual quality validation** — out_ncnn.png vs out_coreml.png 4.4 MB vs 5.9 MB (Core ML çıktısı %26 daha küçük). Subjective olarak kalite eşit olabilir veya ncnn daha detay tutmuş olabilir. Step 3 benchmark suite'inde SSIM/PSNR formal ölçüm yapılır.

---

## Files Generated

- `tools/coreml-conversion/spike_inspect.py` — model inspection script
- `tools/coreml-conversion/mini_bench.py` — A/B benchmark script
- `tools/coreml-conversion/hf-model/RealESRGAN.mlmodel` (gitignored, 64 MB)
- `tools/coreml-conversion/RealESRGAN.mlmodel.zip` (gitignored, source archive)
- `tools/coreml-conversion/fixture-512.png` (kept as benchmark fixture)
- `tools/coreml-conversion/out_ncnn.png` (4.4 MB sample output)
- `tools/coreml-conversion/out_coreml.png` (5.9 MB sample output)
- `tools/coreml-conversion/spike_results.json` (inspection raw output)
- `tools/coreml-conversion/bench_log.txt` (benchmark log)

---

## Wisdom Candidates (post-Step 0)

1. **Spike-before-conversion saves time when pre-built models exist** — 1.5h spike saved 6h Step 1. Pattern: always check HuggingFace + community Core ML repos before assuming conversion is mandatory.
2. **Empirical A/B beats theoretical format preference** — mlProgram is "preferred" but legacy neuralNetwork delivered 5× speedup; runtime works what runtime works.
3. **HF LFS pointer + direct curl bypass** — when git-lfs not available, HF API tree listing + `resolve/main/<file>` curl works for public models.

---

**Karar bekleniyor:** Step 1 SKIP onayı + Step 2 başlangıç direktifi.
