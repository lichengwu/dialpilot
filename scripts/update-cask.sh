#!/bin/sh
# Point the Homebrew cask at the DMG in dist/ (version + sha256).
#
#   ./scripts/make-dmg.sh            # produces dist/DialPilot-<version>.dmg(.sha256)
#   ./scripts/update-cask.sh         # rewrites Casks/dialpilot.rb in the tap
#   ./scripts/update-cask.sh --commit
#
# The tap checkout is found next to this repo by default (../homebrew-tap);
# override with DIALPILOT_TAP_DIR. Run this *after* the release asset is
# uploaded, because the cask URL must resolve for `brew install` to work.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TAP_DIR=${DIALPILOT_TAP_DIR:-$PROJECT_DIR/../homebrew-tap}
CASK="$TAP_DIR/Casks/dialpilot.rb"
INFO_PLIST="$PROJECT_DIR/AppResources/Info.plist"

COMMIT=0
for arg in "$@"; do
    case "$arg" in
        --commit) COMMIT=1 ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
DMG="$PROJECT_DIR/dist/DialPilot-$VERSION.dmg"

[ -f "$CASK" ] || { echo "Missing cask: $CASK (set DIALPILOT_TAP_DIR)" >&2; exit 1; }
[ -f "$DMG" ] || { echo "Missing $DMG — run ./scripts/make-dmg.sh first" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

# Each pattern must match exactly once; anything else means the cask drifted and
# a blind substitution would corrupt it.
check_once() {
    count=$(grep -c "$1" "$CASK" || true)
    [ "$count" -eq 1 ] || {
        echo "Expected exactly one '$1' line in $CASK, found $count" >&2
        exit 1
    }
}
check_once '^  version "'
check_once '^  sha256 "'

tmp="$CASK.tmp.$$"
sed -e "s|^  version \".*\"$|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" \
    "$CASK" > "$tmp"
mv "$tmp" "$CASK"

echo "cask:    $CASK"
echo "version: $VERSION"
echo "sha256:  $SHA"

if [ "$COMMIT" -eq 1 ]; then
    git -C "$TAP_DIR" add Casks/dialpilot.rb
    git -C "$TAP_DIR" commit -q -m "dialpilot $VERSION"
    git -C "$TAP_DIR" push -q origin HEAD
    echo "pushed"
fi
