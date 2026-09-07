# Changelog

All notable versions of **AI-autoenhance-watermark** (Watermark Tool).

## Unreleased — enhancer-v3-skin-safe

**Status:** quality-first retained, with portrait/skin protections after people photos looked worse than the `v2026.09.07` baseline.

### Changes

- **Skin-safe path:** Vision face detect + `portrait`/`event` AI scenes soften exposure/shadows, cut vibrance/sharpen/contrast, and skip stacking vibrance/sharpen on the subject second pass
- **Denoise:** no longer applied on clean low-ISO frames; further reduced when faces are present (avoids waxy skin)
- **Milder quality-first boosts** overall; people plans use tighter caps than landscape/stage
- Resume fingerprint `enhancer-v3-skin-safe` so prior quality-first outputs re-run

## Unreleased — enhancer-v3 quality-first (M1 32GB personal)

**Status:** source updated for quality-over-speed personal Nikon Z6 use; skin-safe refinements above.

### Changes

- **Quality first mode (default on):** slow batches OK; utility/background QoS; Ollama uses half the CPU threads + `nice`-style priority so other Mac work stays usable
- **Larger local VL default:** `qwen3-vl:8b-instruct` (falls back to `4b-instruct` if missing); editable model tag in UI; 10-minute→60-minute keep-alive; up to 600s AI attempts
- **ISO-aware denoise** before tone (Core Image), tuned for Z6 high-ISO NEFs
- **Full AI analysis default** (`All images`); larger 1536px analysis preview when quality-first
- **After RawTherapee:** gentle measured polish still runs in quality-first (no longer skip CI entirely)
- **Export defaults:** JPEG 95%, Compressed JPEG output for NEF-friendly personal batches
- Offline package defaults to 8b instruct (`MODEL=qwen3-vl:4b-instruct` still overrides)

## Unreleased — enhancer-v2 (AI quality + stronger batch enhance)

Superseded by enhancer-v3 quality-first above for personal use priorities.

### Changes

- Stronger measured auto-enhance; soft AI gating; preserveColor; feathered subject path; no `autoAdjustmentFilters` stacking

## 2026.09.07 — snapshot

Frozen baseline tag `v2026.09.07`. See git history for details.

### Links

- Repository: https://github.com/drmichaelnguyen/AI-autoenhance-watermark
