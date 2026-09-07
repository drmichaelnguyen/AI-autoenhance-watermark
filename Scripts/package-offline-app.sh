#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLLAMA_VERSION="v0.33.1"
MODEL="qwen3-vl:4b-instruct"
RUNTIME_ARCHIVE="$ROOT/.packaging-cache/ollama-darwin-$OLLAMA_VERSION.tgz"
RUNTIME_URL="https://github.com/ollama/ollama/releases/download/$OLLAMA_VERSION/ollama-darwin.tgz"
APP="$ROOT/dist/WatermarkTool.app"
RESOURCES="$APP/Contents/Resources"
MODELS="$RESOURCES/Models"
MODEL_CACHE="$ROOT/.packaging-cache/models-qwen3-vl-4b-instruct"
ZIP="$ROOT/dist/WatermarkTool-Offline-Apple-Silicon.zip"
PACKAGE_PORT="11436"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

mkdir -p "$ROOT/.packaging-cache" "$ROOT/dist"
if [[ ! -f "$RUNTIME_ARCHIVE" ]]; then
    echo "Downloading pinned Ollama runtime $OLLAMA_VERSION..."
    curl --fail --location --progress-bar -o "$RUNTIME_ARCHIVE" "$RUNTIME_URL"
fi

echo "Building Watermark Tool for Apple Silicon..."
cd "$ROOT"
swift build -c release --arch arm64

if [[ ! -d "$MODEL_CACHE/manifests" && -d "$MODELS/manifests" ]]; then
    echo "Caching the already-downloaded model for reproducible rebuilds..."
    mkdir -p "$MODEL_CACHE"
    cp -cR "$MODELS/." "$MODEL_CACHE/"
fi

echo "Assembling app bundle..."
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$RESOURCES/Licenses" "$MODEL_CACHE"
cp "$ROOT/.build/arm64-apple-macosx/release/WatermarkTool" "$APP/Contents/MacOS/WatermarkTool"
cp "$ROOT/WatermarkTool.app/Contents/Info.plist" "$APP/Contents/Info.plist"
tar -xzf "$RUNTIME_ARCHIVE" -C "$RESOURCES"
chmod +x "$APP/Contents/MacOS/WatermarkTool" "$RESOURCES/ollama" "$RESOURCES/llama-server" "$RESOURCES/llama-quantize"

echo "Adding third-party licenses..."
curl --fail --location --silent --show-error \
    -o "$RESOURCES/Licenses/Ollama-MIT-LICENSE.txt" \
    "https://raw.githubusercontent.com/ollama/ollama/$OLLAMA_VERSION/LICENSE"
curl --fail --location --silent --show-error \
    -o "$RESOURCES/Licenses/Qwen3-VL-Apache-2.0-LICENSE.txt" \
    "https://ollama.com/library/qwen3-vl:4b-instruct/blobs/7339fa418c9a"

echo "Staging bundled model $MODEL (about 3.3 GB)..."
export OLLAMA_HOST="127.0.0.1:$PACKAGE_PORT"
export OLLAMA_MODELS="$MODEL_CACHE"
export OLLAMA_KEEP_ALIVE="0"
"$RESOURCES/ollama" serve >"$ROOT/.packaging-cache/package-ollama.log" 2>&1 &
SERVER_PID=$!

READY=0
for _ in {1..100}; do
    if curl --silent --fail "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
        READY=1
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Bundled runtime exited during packaging. See .packaging-cache/package-ollama.log" >&2
        exit 1
    fi
    sleep 0.2
done
if [[ "$READY" != "1" ]]; then
    echo "Bundled runtime did not start during packaging. See .packaging-cache/package-ollama.log" >&2
    exit 1
fi

"$RESOURCES/ollama" pull "$MODEL"
curl --silent --fail "$OLLAMA_HOST/api/tags" |
    /usr/bin/python3 -c 'import json,sys; names=[m["name"] for m in json.load(sys.stdin)["models"]]; assert "qwen3-vl:4b-instruct" in names, names'
cleanup
SERVER_PID=""
mkdir -p "$MODELS"
cp -cR "$MODEL_CACHE/." "$MODELS/"

echo "Applying ad-hoc signature..."
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Creating transferable ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Created:"
du -sh "$APP" "$ZIP"
echo "$ZIP"
