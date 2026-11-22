#!/bin/sh
# Build DialPilot.app (release) and pack it into a distributable DMG.
#
#   ./scripts/make-dmg.sh                 # build + package -> dist/DialPilot-<version>.dmg
#   ./scripts/make-dmg.sh --skip-build    # package the existing .build/app/DialPilot.app
#
# The DMG contains DialPilot.app plus an /Applications symlink, so the user
# drags one icon onto the other. The disk image is signed with the same
# identity build-app.sh used (Apple Development when available).
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="DialPilot"
APP_DIR="$PROJECT_DIR/.build/app/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
INFO_PLIST="$PROJECT_DIR/AppResources/Info.plist"

SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [ "$SKIP_BUILD" -eq 0 ]; then
    "$PROJECT_DIR/build-app.sh" >/dev/null
fi
if [ ! -d "$APP_DIR" ]; then
    echo "Missing $APP_DIR — run ./build-app.sh first." >&2
    exit 1
fi

# Same identity resolution as build-app.sh: a stable signature keeps the
# user's Input Monitoring / Accessibility grants across upgrades.
SIGNING_IDENTITY=${DIALPILOT_SIGNING_IDENTITY:-}
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/^[[:space:]]*[0-9]*) [0-9A-F]* "\(Apple Development:.*\)"$/\1/p' \
            | head -n 1
    )
    [ -n "$SIGNING_IDENTITY" ] || SIGNING_IDENTITY=-
fi

STAGE_ROOT=$(mktemp -d "$PROJECT_DIR/.build/dialpilot-dmg.XXXXXX")
cleanup() {
    rm -rf -- "$STAGE_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$STAGE_ROOT/$APP_NAME"
ditto "$APP_DIR" "$STAGE_ROOT/$APP_NAME/$APP_NAME.app"
ln -s /Applications "$STAGE_ROOT/$APP_NAME/Applications"

codesign --verify --strict "$STAGE_ROOT/$APP_NAME/$APP_NAME.app"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

# UDZO = zlib-compressed, read-only: the format every browser downloads without
# extra tooling. HFS+ keeps the /Applications symlink semantics identical to
# other Mac DMGs.
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_ROOT/$APP_NAME" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG_PATH"

codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
echo "sha256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo "size:   $(du -h "$DMG_PATH" | cut -f1)"
