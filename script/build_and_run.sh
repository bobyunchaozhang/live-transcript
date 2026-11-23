#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LiveTranscript"
BUNDLE_ID="local.bob.LiveTranscript"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
BUILD_FLAGS=(-c debug)
PACKAGE_VARIANT=""
case "$MODE" in
    run|--debug|--logs|--telemetry|--verify) ;;
    --package)
        PACKAGE_VARIANT=universal
        PACKAGE_ARCHS=(arm64 x86_64)
        ;;
    --package-arm64)
        PACKAGE_VARIANT=arm64
        PACKAGE_ARCHS=(arm64)
        ;;
    *)
        echo "usage: $0 [--debug|--logs|--telemetry|--verify|--package|--package-arm64]" >&2
        exit 2
        ;;
esac

if [[ -n "$PACKAGE_VARIANT" ]]; then
    BUILD_FLAGS=(-c release --scratch-path "$ROOT_DIR/.build/$PACKAGE_VARIANT")
    for arch in "${PACKAGE_ARCHS[@]}"; do
        BUILD_FLAGS+=(--arch "$arch")
    done
    APP_DIR="$ROOT_DIR/dist/$PACKAGE_VARIANT/会听.app"
fi

APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
ASR_ASSETS="$(./script/prepare_bilingual_assets.sh)"
swift build "${BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/$APP_NAME"
if [[ -n "$PACKAGE_VARIANT" ]]; then
    for arch in "${PACKAGE_ARCHS[@]}"; do
        /usr/bin/lipo -verify_arch "$arch" "$BUILD_BINARY"
    done
else
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/ThirdParty" "$APP_DIR/Contents/Frameworks"
for library in "$ASR_ASSETS"/Frameworks/*.dylib; do
    destination="$APP_DIR/Contents/Frameworks/$(basename "$library")"
    if [[ "$PACKAGE_VARIANT" == arm64 ]]; then
        /usr/bin/lipo -thin arm64 "$library" -output "$destination"
        /usr/bin/codesign --force --sign - "$destination"
    else
        /bin/cp -p "$library" "$destination"
    fi
done
/bin/cp -R "$ASR_ASSETS/Resources/." "$APP_DIR/Contents/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/script/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR"/script/ThirdParty/*.txt "$APP_DIR/Contents/Resources/ThirdParty/"
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
    --package|--package-arm64)
        /usr/bin/codesign --verify --deep --strict "$APP_DIR"
        VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
        ARCHIVE="$ROOT_DIR/dist/huiting-$VERSION-macos-$PACKAGE_VARIANT.zip"
        /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE.tmp"
        mv -f "$ARCHIVE.tmp" "$ARCHIVE"
        printf '%s\n' "$ARCHIVE"
        ;;
esac
