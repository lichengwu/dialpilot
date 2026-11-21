#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_NAME="DialPilot"
BUILD_CONFIGURATION="release"
OUTPUT_DIR="$PROJECT_DIR/.build/app"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
EXPECTED_APP_DIR="$PROJECT_DIR/.build/app/DialPilot.app"
SIGNING_IDENTITY=${DIALPILOT_SIGNING_IDENTITY:--}

if [ "$(uname -m)" != "arm64" ]; then
    echo "DialPilot currently supports Apple Silicon (arm64) only." >&2
    exit 1
fi

cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIGURATION" --arch arm64 --disable-sandbox

BIN_DIR=$(swift build -c "$BUILD_CONFIGURATION" --arch arm64 --disable-sandbox --show-bin-path)
STAGING_ROOT=$(mktemp -d "$PROJECT_DIR/.build/dialpilot-app.XXXXXX")
STAGING_APP="$STAGING_ROOT/$APP_NAME.app"
CONTENTS_DIR="$STAGING_APP/Contents"

cleanup() {
    rm -rf -- "$STAGING_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/DialPilot" "$CONTENTS_DIR/MacOS/DialPilot"
cp "$BIN_DIR/dialpilotctl" "$CONTENTS_DIR/MacOS/dialpilotctl"
cp "$PROJECT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --sign "$SIGNING_IDENTITY" --identifier dev.lichengwu.dialpilot "$STAGING_APP"

if [ "$APP_DIR" != "$EXPECTED_APP_DIR" ]; then
    echo "Refusing to replace unexpected app path: $APP_DIR" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf -- "$APP_DIR"
ditto "$STAGING_APP" "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "$APP_DIR"
