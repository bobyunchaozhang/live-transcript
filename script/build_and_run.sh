#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LiveTranscript"
BUNDLE_ID="local.bob.LiveTranscript"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
BUILD_FLAGS=(-c debug)
case "$MODE" in
    run|--debug|--logs|--telemetry|--verify) ;;
    --package)
        BUILD_FLAGS=(-c release --arch arm64 --arch x86_64 --scratch-path "$ROOT_DIR/.build/universal")
        APP_DIR="$ROOT_DIR/dist/universal/会听.app"
        ;;
    *)
        echo "usage: $0 [--debug|--logs|--telemetry|--verify|--package]" >&2
        exit 2
        ;;
esac

APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
ASR_ASSETS="$(./script/prepare_bilingual_assets.sh)"
swift build "${BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/$APP_NAME"
if [[ "$MODE" == --package ]]; then
    /usr/bin/lipo -verify_arch arm64 "$BUILD_BINARY"
    /usr/bin/lipo -verify_arch x86_64 "$BUILD_BINARY"
else
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
for library in "$ASR_ASSETS"/Frameworks/*.dylib; do
    /bin/cp -p "$library" "$APP_DIR/Contents/Frameworks/"
done
/bin/cp -R "$ASR_ASSETS/Resources/." "$APP_DIR/Contents/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/script/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Sources/EchoDSP/Vendor/COPYING" "$APP_DIR/Contents/Resources/ThirdParty/SpeexDSP-LICENSE.txt"
cp "$ROOT_DIR/script/AppIcon.icns" "$APP_DIR/Contents/Resources/VoiceInputAppIcon.icns"
cp "$ROOT_DIR/script/VoiceInput.png" "$APP_DIR/Contents/Resources/"
rm -f "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -f "$APP_DIR/Contents/Resources/SpeexDSP-LICENSE.txt"
/usr/bin/codesign --force --sign - "$APP_DIR"

open_app() {
    /usr/bin/open -n "$APP_DIR"
}

case "$MODE" in
    run) open_app ;;
    --debug) lldb -- "$APP_BINARY" ;;
    --logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME"
        ;;
    --package)
        /usr/bin/codesign --verify --deep --strict "$APP_DIR"
        VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
        ARCHIVE="$ROOT_DIR/dist/huiting-$VERSION-macos-universal.zip"
        /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE.tmp"
        mv -f "$ARCHIVE.tmp" "$ARCHIVE"
        printf '%s\n' "$ARCHIVE"
        ;;
esac
