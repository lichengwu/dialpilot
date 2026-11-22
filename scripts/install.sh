#!/bin/sh
# Install DialPilot on this Mac without a toolchain or a browser.
#
#   curl -fsSL https://raw.githubusercontent.com/lichengwu/dialpilot/main/scripts/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --version 1.1.2
#
# Why a script instead of "download the DMG": files saved by a browser carry
# com.apple.quarantine, so Gatekeeper inspects them on first launch and — on
# macOS 15 and later — there is no Control-click bypass left. curl does not set
# that flag, so an installer that downloads and verifies the image itself
# produces an app that simply opens. Integrity comes from the release's
# published SHA-256, which this script checks before touching /Applications.
set -eu

REPO="lichengwu/dialpilot"
APP_NAME="DialPilot"
BUNDLE_PATH="DialPilot.app"
TARGET_DIR=${DIALPILOT_INSTALL_DIR:-/Applications}
VERSION=${DIALPILOT_VERSION:-}

usage() {
    cat <<'EOF'
Install DialPilot (macOS menu-bar companion for the Ulanzi AU05 dial).

Usage:
  install.sh [--version <x.y.z>] [--dir </Applications>]

Environment:
  DIALPILOT_VERSION       same as --version
  DIALPILOT_INSTALL_DIR   same as --dir

Without --version the latest GitHub release is resolved at run time.
EOF
}

die() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || die "--version needs a value"
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION=${1#--version=}
            shift
            ;;
        --dir)
            [ $# -ge 2 ] || die "--dir needs a value"
            TARGET_DIR="$2"
            shift 2
            ;;
        --dir=*)
            TARGET_DIR=${1#--dir=}
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || die "this installer is macOS-only"
[ "$(uname -m)" = "arm64" ] || die "DialPilot is Apple Silicon only (arm64)"
OS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$OS_MAJOR" -ge 13 ] || die "DialPilot needs macOS 13 or later (found $(sw_vers -productVersion))"

if [ -z "$VERSION" ]; then
    printf 'Resolving latest release… '
    EFFECTIVE_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
        "https://github.com/$REPO/releases/latest") \
        || die "could not reach github.com"
    VERSION=${EFFECTIVE_URL##*/}
    VERSION=${VERSION#v}
    [ -n "$VERSION" ] || die "could not determine the latest version"
    printf '%s\n' "$VERSION"
fi
VERSION=${VERSION#v}

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_URL="https://github.com/$REPO/releases/download/v$VERSION/$DMG_NAME"
SHA_URL="$DMG_URL.sha256"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dialpilot-install.XXXXXX")
MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dialpilot-mnt.XXXXXX")
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf -- "$WORK_DIR" "$MOUNT_DIR"
}
trap cleanup EXIT HUP INT TERM

printf 'Downloading %s\n' "$DMG_NAME"
curl -fsSL --retry 3 --retry-delay 2 -o "$WORK_DIR/$DMG_NAME" "$DMG_URL" \
    || die "download failed: $DMG_URL"
curl -fsSL --retry 3 --retry-delay 2 -o "$WORK_DIR/$DMG_NAME.sha256" "$SHA_URL" \
    || die "checksum download failed: $SHA_URL (release is missing its .sha256 asset)"

EXPECTED=$(cut -d' ' -f1 "$WORK_DIR/$DMG_NAME.sha256")
ACTUAL=$(shasum -a 256 "$WORK_DIR/$DMG_NAME" | cut -d' ' -f1)
[ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch — refusing to install
  expected $EXPECTED
  actual   $ACTUAL"
printf 'Checksum OK (%s)\n' "$ACTUAL"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    printf 'Quitting the running %s…\n' "$APP_NAME"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
fi

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$WORK_DIR/$DMG_NAME" -quiet \
    || die "could not mount the disk image"
MOUNTED=1
[ -d "$MOUNT_DIR/$BUNDLE_PATH" ] || die "the disk image does not contain $BUNDLE_PATH"

mkdir -p "$TARGET_DIR" 2>/dev/null || true
[ -w "$TARGET_DIR" ] || die "$TARGET_DIR is not writable — re-run with sudo, or pass --dir ~/Applications"
rm -rf -- "$TARGET_DIR/$BUNDLE_PATH"
ditto "$MOUNT_DIR/$BUNDLE_PATH" "$TARGET_DIR/$BUNDLE_PATH" || die "copy to $TARGET_DIR failed"

hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
MOUNTED=0

# Only the browser download path produces a quarantine flag; strip it anyway so
# the app opens even if this script is run from a quarantined copy.
xattr -dr com.apple.quarantine "$TARGET_DIR/$BUNDLE_PATH" 2>/dev/null || true
codesign --verify --strict "$TARGET_DIR/$BUNDLE_PATH" >/dev/null 2>&1 \
    || printf 'warning: signature did not verify; the app may still run\n' >&2

printf '\nInstalled %s %s to %s\n\n' "$APP_NAME" "$VERSION" "$TARGET_DIR/$BUNDLE_PATH"
cat <<'EOF'
Next:
  1. Quit Ulanzi Studio completely (two hosts fight over the dial).
  2. Launch DialPilot from /Applications.
  3. System Settings → Privacy & Security → allow Input Monitoring and Accessibility.
EOF
