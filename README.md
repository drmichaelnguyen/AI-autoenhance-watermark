# Watermark Tool

**Version:** `enhancer-v3-skin-safe` (unreleased; builds on `2026.09.07`)  
**Repo:** [drmichaelnguyen/AI-autoenhance-watermark](https://github.com/drmichaelnguyen/AI-autoenhance-watermark)

Native macOS batch **AI auto-enhance + watermark** for personal Nikon Z6 / NEF work. Built with SwiftUI, Core Image, Vision, and ImageIO. All AI runs locally. **Quality over speed** is the default: batches may take hours; the app and embedded Ollama run at background/utility priority so other Mac work stays usable.

See [CHANGELOG.md](CHANGELOG.md) for enhancer-v3 / skin-safe details.

## Processing pipeline

The app keeps source RAW files untouched. RAW files use RawTherapee's CLI when **Auto-enhance image** is enabled and the executable is installed; otherwise ImageIO supplies the source image. Non-RAW auto-enhancement uses a **bounded** measured Core Image plan (exposure, shadows/highlights, contrast, vibrance, sharpening)—not uncontrolled `autoAdjustmentFilters`.

The processing order is: develop or decode -> optional ISO denoise -> measure -> optional local AI scene analysis (soft bias) -> bounded enhancement (global and/or feathered subject) -> watermark -> one output encode. Measurement reads display-referred RGB samples after decode; intermediate CI work uses extended sRGB; the final watermark context is sRGB device RGB.

Measurements include luminance 20th, 50th, and 99th percentiles, shadow density, highlight headroom, and per-channel clipping. Exposure is capped near 0.72 stops and shadow lifting near 0.48 (tighter when faces/`portrait`/`event` are detected). Deep noisy shadows suppress lifting. AI analysis **biases** the plan instead of hard-zeroing treatments like `minimal` or `preserve_stage_lighting`. `preserveColor` skips vibrance so stage/colored lighting is kept. People photos use a **skin-safe** path: much less vibrance/sharpen, reduced denoise, and a subject second pass that lifts tone only (no stacked color/sharpen on skin).

## Bundled local AI analysis

Defaults: **Quality first** on, **Auto-enhance** on, **AI subject enhancement** on, **AI analysis** All images, model **`qwen3-vl:8b-instruct`** (falls back to `4b-instruct`). Selective mode still available. Ollama classifies scene/lighting and softly biases the measured plan. It cannot invent arbitrary edit values or masks. Invalid JSON / timeouts fall back to measurement-only without failing the batch.

The offline package stages the chosen instruct VL model (default 8b for quality). Instruct variants are required so short JSON is not displaced by reasoning tokens. The app starts its own Ollama child on `11435` at background priority with roughly half the CPU threads reserved for other work. Quality-first analysis uses a 1536px preview, longer timeouts (up to 600s), and keeps the model warm for 60 minutes.

The **Test local AI** button verifies that the embedded runtime starts and the bundled model is visible. Runtime output is written to `~/Library/Application Support/WatermarkTool/embedded-ollama.log`. Per-image AI decisions, enhancement plans, and fallbacks are written to `watermark-work.log` in the output folder.

## Batch safety

The app processes one image at a time, keeps the AI request serialized, releases each image after export, and reports progress. Cancel stops between images. `.watermark-status.json` fingerprints include `enhancer-v3-skin-safe`. JPEG default quality is 0.95. ISO-aware denoise runs before tone for higher ISO; it is skipped on clean low-ISO frames and further reduced when faces are present.

## Run (on Mac)

```sh
swift run
```

Choose an input folder and an output folder, enter the watermark text, then set its font, corner, opacity, size, and bottom offset. Leave **Quality first**, Auto-enhance, AI subject, and All-images analysis on for best personal Z6 results. Batches can run overnight. Originals are never overwritten.

For high-quality RAW enhancement, install RawTherapee 5.13 with Homebrew:

```sh
brew install --cask rawtherapee
```

Enable **Auto-enhance image** and choose **Compressed JPEG** for NEF/RAW input. The app uses RawTherapee's command-line processor for RAW development, then applies the measured/subject path afterward when configured.

## Build a standalone app

Create the complete Apple Silicon offline package with:

```sh
Scripts/package-offline-app.sh
```

The script downloads the pinned official Ollama runtime, stages the instruct VL model (default `qwen3-vl:8b-instruct`; override with `MODEL=...`), builds the arm64 app, ad-hoc signs it, and creates `dist/WatermarkTool-Offline-Apple-Silicon.zip`. Allow several GB for the 8b model. M1 32GB is the intended personal target.
