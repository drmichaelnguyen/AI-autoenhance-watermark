# Watermark Tool

**Version:** `2026.09.07`  
**Repo:** [drmichaelnguyen/AI-autoenhance-watermark](https://github.com/drmichaelnguyen/AI-autoenhance-watermark)

Native macOS batch watermark utility built with SwiftUI and ImageIO.

See [CHANGELOG.md](CHANGELOG.md) for what shipped in this snapshot and **pending** AI enhancement quality work (held; not implemented yet).

## Processing pipeline

The app keeps source RAW files untouched. RAW files use RawTherapee's CLI when **Auto-enhance image** is enabled and the executable is installed; otherwise ImageIO supplies the source image. Non-RAW auto-enhancement uses measured, bounded Core Image adjustments rather than a second uncontrolled automatic adjustment.

The processing order is: develop or decode -> measure -> optional scene analysis -> bounded enhancement -> resize (when a future output dimension is configured) -> watermark -> one output encode. The current app has no resize control, so source dimensions are retained. Measurement reads display-referred RGB samples after decode; the final watermark context is sRGB device RGB. No Lightroom slider values are used internally.

Measurements include luminance 20th, 50th, and 99th percentiles, shadow density, highlight headroom, and per-channel clipping. Exposure is capped at 0.35 stops and shadow lifting at 0.28. Deep noisy shadows suppress lifting. The app does not infer pixel masks from AI text; the existing Vision subject toggle remains a separate optional feature.

## Bundled local AI analysis

AI analysis is **Off** by default. **Selective** (the default when enabled) calls Ollama only for difficult images; **All images** is intended for evaluation. Ollama may classify the scene and lighting and select one of `minimal`, `global_exposure`, `shadow_lift`, `subject_lift`, `preserve_stage_lighting`, or `review`. It cannot provide arbitrary edit values or masks. Invalid JSON, unavailable Ollama, timeouts, and failed retries use deterministic measurements without failing the batch.

The offline package includes the pinned Ollama runtime and non-thinking `qwen3-vl:4b-instruct` model. The instruct variant is required so the short structured response is not displaced by hidden reasoning tokens. The app starts and stops its own child process on private localhost port `11435`; it does not use an installed Ollama service and makes no cloud inference calls. The integration sends a downsampled JPEG preview with a maximum dimension of 1024 pixels, JSON-schema-constrained output, temperature 0, a 160-token output limit, two bounded attempts, and a 180-second per-attempt timeout to allow initial model loading. Analysis is cached in `.watermark-ai-cache.json` using source size/date, model, and prompt version.

The **Test local AI** button verifies that the embedded runtime starts and the bundled model is visible. Runtime output is written to `~/Library/Application Support/WatermarkTool/embedded-ollama.log`. Per-image AI decisions and fallbacks are also written to `watermark-work.log` in the output folder.

## Batch safety

The app processes one image at a time, keeps the AI request serialized, releases each image after export, and reports progress. Cancel stops between images. `.watermark-status.json` stores a fingerprint of each completed source and its settings, allowing a later run to resume without creating another output for unchanged work. Output is written to a temporary file and moved into place atomically; name collisions receive a numeric suffix. JPEG is encoded once after watermarking. Metadata/GPS controls and output resizing are not yet exposed by this small integration.

## Run

```sh
swift run
```

Choose an input folder and an output folder, enter the watermark text, then set its font, corner, opacity, size, and bottom offset. Originals are never overwritten. Supported non-RAW formats can be exported in their original format; RAW files must be exported as JPEG because a composited watermark requires rendering the RAW image.

The Local analysis section includes a **Test local AI** button that verifies both the Ollama service and the requested model. During processing, the in-app work log records every image, AI call/cache/skip/fallback decision, output, and failure. The same history is appended to `watermark-work.log` in the selected output folder.

For high-quality RAW enhancement, install RawTherapee 5.13 with Homebrew:

```sh
brew install --cask rawtherapee
```

Enable **Auto-enhance image** in the app and choose **Compressed JPEG** for NEF/RAW input. The app uses RawTherapee's command-line processor for RAW development, applies the watermark afterward, and removes the temporary rendered file. If RawTherapee is unavailable, the app falls back to Apple's Core Image adjustments.

Enable **AI subject enhancement** to use macOS Vision's on-device foreground segmentation. The detected subject receives automatic exposure, color, and detail adjustments while the background is preserved. This is local processing; no image is uploaded. Sky-specific masking is not included yet.

## Verification

The project was built successfully with `swift build -c debug` on an arm64 Apple Silicon machine. The current Swift toolchain does not provide `XCTest` or Swift Testing, so automated test targets could not be added without making `swift test` fail. The remaining quality gap is to run representative NEF/JPEG fixtures through the batch and record stage timings, memory observations, clipping comparisons, and before-watermark reports. No throughput estimate is claimed here.

## Build a standalone app

Create the complete Apple Silicon offline package with:

```sh
Scripts/package-offline-app.sh
```

The script downloads the pinned official Ollama runtime, stages the approximately 3.3 GB model, includes the required MIT and Apache 2.0 license texts, builds the arm64 app, applies an ad-hoc signature, and creates `dist/WatermarkTool-Offline-Apple-Silicon.zip`. The destination Mac does not need Homebrew, Ollama, a model download, or internet access.

The package targets macOS 14 or later on Apple Silicon. Allow roughly 4 GB of disk space and 8 GB or more of RAM; the intended M1 Mac Studio with 32 GB RAM is comfortably sufficient. Because this personal-use build is ad-hoc signed rather than Apple-notarized, the first launch on another Mac may require Control-clicking the app, choosing **Open**, and confirming once in Gatekeeper.