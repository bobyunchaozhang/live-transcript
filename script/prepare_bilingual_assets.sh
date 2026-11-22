#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT_DIR/.build/bilingual-download"
RUNTIME="sherpa-onnx-v2.0.2-osx-universal2-shared-no-tts-lib"
MODEL="sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05"
DESTINATION="$ROOT_DIR/.build/bilingual-asr-v2.0.2-480ms-universal"

if [[ -f "$DESTINATION/Resources/BilingualSpeech/tokens.txt" ]]; then
    printf '%s\n' "$DESTINATION"
    exit 0
fi

mkdir -p "$CACHE"
STAGING="$(mktemp -d "$CACHE/staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

verified_archive() {
    local url="$1" hash="$2" archive="$3"
    if ! shasum -a 256 --check --status <<< "$hash  $archive" 2>/dev/null; then
        local downloaded="$STAGING/$(basename "$archive")"
        curl -fLsS --retry 2 "$url" -o "$downloaded"
        shasum -a 256 --check --status <<< "$hash  $downloaded"
        mv -f "$downloaded" "$archive"
    fi
}

verified_archive "https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.2/$RUNTIME.tar.bz2" \
    c2ca455a28e177c673bead6b222f4b6555332c85e5e4453d2a768f5cba39b5c1 "$CACHE/runtime.tar.bz2"
verified_archive "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL.tar.bz2" \
    fa5f63d618e5a01526e275a358bb7772e403f84808a4769fba52cffd8160bf74 "$CACHE/model.tar.bz2"

tar -xf "$CACHE/runtime.tar.bz2" -C "$STAGING"
tar -xf "$CACHE/model.tar.bz2" -C "$STAGING"

ASSETS="$STAGING/assets"
mkdir -p "$ASSETS/Frameworks" "$ASSETS/Resources/BilingualSpeech"
for library in libonnxruntime.dylib libsherpa-onnx-c-api.dylib; do
    /usr/bin/lipo -verify_arch arm64 "$STAGING/$RUNTIME/lib/$library"
    /usr/bin/lipo -verify_arch x86_64 "$STAGING/$RUNTIME/lib/$library"
    cp "$STAGING/$RUNTIME/lib/$library" "$ASSETS/Frameworks/$library"
    /usr/bin/codesign --force --sign - "$ASSETS/Frameworks/$library"
done
for file in encoder.int8.onnx decoder.onnx joiner.int8.onnx tokens.txt; do
    cp "$STAGING/$MODEL/$file" "$ASSETS/Resources/BilingualSpeech/$file"
done
if [[ ! -d "$DESTINATION" ]]; then
    mv "$ASSETS" "$DESTINATION"
fi
printf '%s\n' "$DESTINATION"
