#!/bin/sh
# Build DialPilot.app (release) and pack it into a distributable DMG.
#
#   ./scripts/make-dmg.sh                 # build + package -> dist/DialPilot-<version>.dmg
#   ./scripts/make-dmg.sh --skip-build    # package the existing .build/app/DialPilot.app
#
# Release artifacts are signed **ad-hoc** by default, on purpose:
#   * Gatekeeper rejects a non-notarized download either way, so an Apple
#     Development signature buys the downloader nothing;
#   * an Apple Development signature without a timestamp stops verifying once
#     the certificate expires (~1 year), which turns every old release into
#     "app is damaged" for new downloaders. Ad-hoc has no certificate chain,
#     so it never expires.
# A stable local identity still matters for *your own* installed build (macOS
# ties Input Monitoring / Accessibility grants to the signature) — that is
# build-app.sh's job, and this script does not touch .build/app.
#
# Override the release identity when a Developer ID + notarization is available:
#   DIALPILOT_RELEASE_IDENTITY="Developer ID Application: ..." ./scripts/make-dmg.sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="DialPilot"
BUNDLE_ID="dev.lichengwu.dialpilot"
APP_DIR="$PROJECT_DIR/.build/app/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
INFO_PLIST="$PROJECT_DIR/AppResources/Info.plist"

SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
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
SHA_PATH="$DMG_PATH.sha256"
RELEASE_IDENTITY=${DIALPILOT_RELEASE_IDENTITY:--}

if [ "$SKIP_BUILD" -eq 0 ]; then
    "$PROJECT_DIR/build-app.sh" >/dev/null
fi
if [ ! -d "$APP_DIR" ]; then
    echo "Missing $APP_DIR — run ./build-app.sh first." >&2
    exit 1
fi

STAGE_ROOT=$(mktemp -d "$PROJECT_DIR/.build/dialpilot-dmg.XXXXXX")
cleanup() {
    rm -rf -- "$STAGE_ROOT"
}
trap cleanup EXIT HUP INT TERM

STAGED_APP="$STAGE_ROOT/$APP_NAME/$APP_NAME.app"
mkdir -p "$STAGE_ROOT/$APP_NAME"
ditto "$APP_DIR" "$STAGED_APP"
ln -s /Applications "$STAGE_ROOT/$APP_NAME/Applications"

# Re-sign the staged copy only: helpers first, then the bundle seal.
for helper in "$STAGED_APP/Contents/MacOS/"*; do
    if file "$helper" | grep -q "Mach-O"; then
        codesign --force --sign "$RELEASE_IDENTITY" "$helper"
    fi
done
codesign --force --sign "$RELEASE_IDENTITY" --identifier "$BUNDLE_ID" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$SHA_PATH"

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

codesign --force --sign "$RELEASE_IDENTITY" "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

# install.sh and the Homebrew cask both pin this file's value; emit it next to
# the image so the release step can upload it as a second asset.
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$SHA_PATH")")

echo "$DMG_PATH"
echo "identity: $RELEASE_IDENTITY"
echo "sha256:   $(cut -d' ' -f1 "$SHA_PATH")"
echo "size:     $(du -h "$DMG_PATH" | cut -f1)"
