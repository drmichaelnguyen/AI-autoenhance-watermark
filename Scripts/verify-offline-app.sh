#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/WatermarkTool.app}"
RESOURCES="$APP/Contents/Resources"
MODEL="${MODEL:-qwen3-vl:8b-instruct}"
PORT="11437"
TEMP="$(mktemp -d)"
RUNTIME_LOG="$ROOT/.packaging-cache/verify-ollama.log"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TEMP"
}
trap cleanup EXIT INT TERM

test -x "$APP/Contents/MacOS/WatermarkTool"
test -x "$RESOURCES/ollama"
test -d "$RESOURCES/Models"
test -s "$RESOURCES/Licenses/Ollama-MIT-LICENSE.txt"
test -s "$RESOURCES/Licenses/Qwen3-VL-Apache-2.0-LICENSE.txt"
codesign --verify --deep --strict --verbose=2 "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/WatermarkTool")" = "arm64"

export OLLAMA_HOST="127.0.0.1:$PORT"
export OLLAMA_MODELS="$RESOURCES/Models"
export OLLAMA_KEEP_ALIVE="0"
cd "$RESOURCES"
: >"$RUNTIME_LOG"
./ollama serve >"$RUNTIME_LOG" 2>&1 &
SERVER_PID=$!

READY=0
for _ in {1..100}; do
    if curl --silent --fail "$OLLAMA_HOST/api/tags" >"$TEMP/tags.json"; then
        READY=1
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$RUNTIME_LOG" >&2
        exit 1
    fi
    sleep 0.2
done
test "$READY" = "1"
/usr/bin/python3 - "$TEMP/tags.json" "$MODEL" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    names = [model["name"] for model in json.load(handle)["models"]]
assert sys.argv[2] in names, names
PY

/usr/bin/python3 - "$TEMP/test.ppm" <<'PY'
import sys
width = height = 32
with open(sys.argv[1], "wb") as image:
    image.write(f"P6\n{width} {height}\n255\n".encode())
    for y in range(height):
        for x in range(width):
            image.write(bytes((40 + x * 5, 80 + y * 4, 180)))
PY
sips -s format jpeg "$TEMP/test.ppm" --out "$TEMP/test.jpg" >/dev/null
base64 -i "$TEMP/test.jpg" -o "$TEMP/image.b64"

/usr/bin/python3 - "$TEMP/image.b64" "$TEMP/request.json" "$MODEL" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    image = handle.read().replace("\n", "")
schema = {
    "type": "object",
    "properties": {
        "hasBlue": {"type": "boolean"},
    },
    "required": ["hasBlue"],
    "additionalProperties": False,
}
request = {
    "model": sys.argv[3],
    "prompt": "Does this image contain blue? Return only the requested JSON.",
    "images": [image],
    "stream": False,
    "format": schema,
    "options": {"temperature": 0, "num_predict": 16},
}
with open(sys.argv[2], "w") as handle:
    json.dump(request, handle)
PY

curl --silent --show-error --fail --max-time 600 \
    -H "Content-Type: application/json" \
    --data-binary "@$TEMP/request.json" \
    "$OLLAMA_HOST/api/generate" >"$TEMP/response.json"

/usr/bin/python3 - "$TEMP/response.json" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    outer = json.load(handle)
analysis = json.loads(outer["response"])
assert set(analysis) == {"hasBlue"}, analysis
assert isinstance(analysis["hasBlue"], bool), analysis
print("Structured offline vision response:", json.dumps(analysis, sort_keys=True))
PY

cleanup
SERVER_PID=""
echo "Offline app verification passed, including clean runtime shutdown."
