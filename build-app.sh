#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_NAME="DialPilot"
BUILD_CONFIGURATION="release"
OUTPUT_DIR="$PROJECT_DIR/.build/app"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
EXPECTED_APP_DIR="$PROJECT_DIR/.build/app/DialPilot.app"

# Signing identity. macOS keys Accessibility / Input Monitoring grants to
# the code signature: an ad-hoc build gets a new cdhash on every rebuild, so
# each `./build-app.sh` silently invalidated the permissions the user had
# just granted (they'd toggle the switch, the app would still report
# "Permissions required"). Prefer a stable "Apple Development" identity so
# the designated requirement survives rebuilds; fall back to ad-hoc only
# when no identity exists.
SIGNING_IDENTITY=${DIALPILOT_SIGNING_IDENTITY:-}
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/^[[:space:]]*[0-9]*) [0-9A-F]* "\(Apple Development:.*\)"$/\1/p' \
            | head -n 1
    )
    [ -n "$SIGNING_IDENTITY" ] || SIGNING_IDENTITY=-
fi

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
cp "$PROJECT_DIR/AppResources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

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
