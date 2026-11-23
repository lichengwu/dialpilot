#!/bin/sh
# Build DialPilot.app (release) and pack it into a distributable DMG.
#
#   ./scripts/make-dmg.sh                 # build + package -> dist/DialPilot-<version>.dmg
#   ./scripts/make-dmg.sh --skip-build    # package the existing .build/app/DialPilot.app
#
# Release artifacts are signed with the fixed self-signed identity
# "DialPilot Release" (scripts/create-signing-cert.sh). Why not ad-hoc:
#   * TCC pins Input Monitoring / Accessibility grants to the designated
#     requirement; ad-hoc's requirement is the binary cdhash, so EVERY
#     release invalidated the grants. With the fixed certificate the
#     requirement is `identifier + certificate leaf` — stable across
#     releases, grants survive updates.
#   * The certificate is valid 20 years and self-signed (no chain to
#     expire); Gatekeeper behaviour is the same as ad-hoc (not notarized).
# Falls back to ad-hoc ONLY if the identity is absent (e.g. a contributor's
# machine) — such builds are for local testing, never for publishing.
# This script does not touch .build/app (your locally installed build keeps
# its Apple Development identity).
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

# Prefer the fixed release identity; ad-hoc is a local-only fallback.
if [ -n "${DIALPILOT_RELEASE_IDENTITY:-}" ]; then
    RELEASE_IDENTITY=$DIALPILOT_RELEASE_IDENTITY
elif security find-identity -p codesigning 2>/dev/null | grep -q '"DialPilot Release"'; then
    RELEASE_IDENTITY="DialPilot Release"
else
    RELEASE_IDENTITY="-"
    echo "warning: 'DialPilot Release' identity not found — falling back to ad-hoc." >&2
    echo "warning: ad-hoc builds must NOT be published (grants break on every update)." >&2
    echo "warning: run scripts/create-signing-cert.sh (maintainer) or use CI releases." >&2
fi

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

# Publishing gate: a real release must carry the certificate-anchored
# requirement, never a cdhash one. DIALPILOT_ALLOW_ADHOC=1 opts out for
# local experiments only.
if [ "${DIALPILOT_ALLOW_ADHOC:-0}" != "1" ]; then
    DR=$(codesign -d -r- "$STAGED_APP" 2>&1 | grep '^designated' || true)
    case "$DR" in
        *"certificate leaf"*) ;;
        *)
            echo "refusing to package: designated requirement is not certificate-anchored:" >&2
            echo "  $DR" >&2
            echo "publishing this would break TCC grants on every update." >&2
            exit 1
            ;;
    esac
fi

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
