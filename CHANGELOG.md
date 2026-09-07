# Changelog

All notable versions of **AI-autoenhance-watermark** (Watermark Tool).

## 2026.09.07 — snapshot (pending AI quality work)

**Status:** frozen baseline before enhancer redesign. No AI-quality fixes in this tag yet.

### Shipped in this version

- Native macOS SwiftUI batch watermark app (`Sources/WatermarkToolApp.swift`)
- Watermark controls: text, font, corner, direction, opacity, height, bottom offset
- **Auto-enhance:** measured, bounded Core Image exposure (≤ 0.35 EV) and shadow lift (≤ 0.28); RawTherapee CLI path for RAW when installed
- **AI analysis (optional):** bundled Ollama + `qwen3-vl:4b-instruct` on localhost `11435`; scene/lighting classification only; gates the measured plan
- **AI subject enhancement (optional):** Vision foreground mask + Apple `autoAdjustmentFilters` on subject
- Batch safety: one image at a time, resume via `.watermark-status.json`, work log, AI analysis cache
- Offline packaging scripts (`Scripts/package-offline-app.sh`, `Scripts/verify-offline-app.sh`)

### Documented investigation (not yet implemented)

Investigation on 2026-09-07 found why AI-edited results often look worse than non-AI auto-enhance:

1. **AI subject enhancement** uses unbounded `CIImage.autoAdjustmentFilters(options: nil)` — opaque WB/contrast/color edits, unlike the capped measured path.
2. **Subject/background discontinuity** — subject is graded differently from the rest; mask is not feathered.
3. **Double processing** when both auto-enhance and AI subject enhancement are on.
4. **AI analysis hard-gates** the plan (`minimal` / `preserve_stage_lighting` / `review` can zero exposure and shadow lift) instead of softly biasing measurements.
5. **`preserveColor` is computed but never applied** by the renderer.
6. Highlight adjust still runs when auto-enhance is on even if shadow lift is zero; final export is always 8-bit sRGB (JPEG default quality 0.85).
7. UI copy oversells auto-enhance (“contrast, color, and sharpness”); code only does exposure + highlight/shadow.

### Pending changes (next version)

Hold implementation until after this snapshot. Planned work:

- [ ] Replace Vision `autoAdjustmentFilters` with the same (or gentler) bounded measured plan on the subject only
- [ ] Feather / soften the subject mask before blend
- [ ] Avoid stacking: subject path + global auto-enhance should not double-tone
- [ ] Soften AI analysis gating: bias the plan instead of muting enhancement on `minimal` / misclassified treatments
- [ ] Honor `preserveColor` / `preserve_stage_lighting` in the renderer
- [ ] Skip or reduce highlight adjust when no shadow lift is planned
- [ ] Align UI captions with what each toggle actually does
- [ ] Optional: higher bit-depth / color-managed path before watermark encode

### Links

- Repository: https://github.com/drmichaelnguyen/AI-autoenhance-watermark
