#!/bin/sh
# Cut a release. Default path is CI (mode 2): bump -> commit -> tag -> push,
# then GitHub Actions builds, signs with the project certificate (repo
# secret), publishes the release and updates the tap. The private key never
# leaves the secrets store.
#
#   ./scripts/release.sh 1.1.5            # CI release (asks before pushing)
#   ./scripts/release.sh 1.1.5 --yes      # no confirmation prompt
#   ./scripts/release.sh 1.1.5 --dry-run  # print the plan, touch nothing
#   ./scripts/release.sh 1.1.5 --local    # legacy: build+sign+publish locally
#                                         # (requires the release identity)
#
# Preconditions this script enforces, because every one of them has bitten a
# release before:
#   - clean working tree on `main` (a half-finished edit must not ride along)
#   - CHANGELOG.md already has a "## [<version>]" section (release notes come
#     from it verbatim, so the notes cannot drift from the changelog)
#   - the tag does not exist yet locally or on the remote
#   - `gh` is authenticated
#
# The build number (CFBundleVersion) is incremented automatically; the marketing
# version is the one you pass in.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INFO_PLIST="$PROJECT_DIR/AppResources/Info.plist"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
TAP_DIR=${DIALPILOT_TAP_DIR:-$PROJECT_DIR/../homebrew-tap}
REPO=lichengwu/dialpilot
BRANCH=main

VERSION=
ASSUME_YES=0
DRY_RUN=0
LOCAL_MODE=0

for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --dry-run|-n) DRY_RUN=1 ;;
        --local) LOCAL_MODE=1 ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
        *)
            [ -z "$VERSION" ] || { echo "Only one version argument is accepted" >&2; exit 2; }
            VERSION=$arg
            ;;
    esac
done

die() { echo "release: $*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------- preconditions
[ -n "$VERSION" ] || die "usage: ./scripts/release.sh <version> [--yes] [--dry-run]"
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "version must look like 1.2.3, got '$VERSION'"

cd "$PROJECT_DIR"

[ -z "$(git status --porcelain)" ] \
    || die "working tree is dirty — commit or stash first (release must be reproducible from HEAD)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] \
    || die "not on $BRANCH (currently $(git rev-parse --abbrev-ref HEAD))"

git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION already exists"
if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
    die "tag v$VERSION already exists on origin"
fi

grep -q "^## \[$VERSION\]" "$CHANGELOG" \
    || die "CHANGELOG.md has no '## [$VERSION]' section — write it first, it becomes the release notes"

command -v gh >/dev/null || die "gh CLI is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

if [ "$LOCAL_MODE" -eq 1 ]; then
    [ -d "$TAP_DIR/Casks" ] || die "tap checkout not found at $TAP_DIR (set DIALPILOT_TAP_DIR)"
fi

OLD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
OLD_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
NEW_BUILD=$((OLD_BUILD + 1))
DMG="$PROJECT_DIR/dist/DialPilot-$VERSION.dmg"

step "Release plan"
if [ "$LOCAL_MODE" -eq 1 ]; then
    cat <<PLAN
    mode:         LOCAL (build + sign + publish on this machine)
    version:      $OLD_VERSION ($OLD_BUILD)  ->  $VERSION ($NEW_BUILD)
    tag:          v$VERSION
    dmg:          $DMG
    notes:        CHANGELOG.md section "[$VERSION]"
    cask:         $TAP_DIR/Casks/dialpilot.rb (version + sha256, then push)
    steps:        swift test -> make-dmg -> commit -> tag -> push -> gh release -> update-cask
PLAN
else
    cat <<PLAN
    mode:         CI (GitHub Actions builds, signs with the repo-secret
                  certificate, publishes the release, updates the tap)
    version:      $OLD_VERSION ($OLD_BUILD)  ->  $VERSION ($NEW_BUILD)
    tag:          v$VERSION
    notes:        CHANGELOG.md section "[$VERSION]"
    steps:        bump -> commit -> tag -> push  (CI does the rest)
PLAN
fi

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    printf '\nPush to origin/%s and publish the GitHub release? [y/N] ' "$BRANCH"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "aborted"; exit 1 ;;
    esac
fi

# ---------------------------------------------------------------------- version
step "Bump Info.plist"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] CFBundleShortVersionString -> $VERSION, CFBundleVersion -> $NEW_BUILD"
else
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                            -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
    echo "    now $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST"))"
fi

# ------------------------------------------------------------------------ tests
if [ "$LOCAL_MODE" -eq 1 ]; then
    step "Tests"
    run swift test --arch arm64 --disable-sandbox

    # ---------------------------------------------------------------------- dmg
    step "Build DMG"
    run ./scripts/make-dmg.sh
    if [ "$DRY_RUN" -eq 0 ]; then
        [ -f "$DMG" ] || die "make-dmg.sh did not produce $DMG"
    fi
fi

# --------------------------------------------------------------------- git side
step "Commit and tag"
NOTES=$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { inside = 1; next }
    inside && /^## \[/     { exit }
    inside                 { print }
' "$CHANGELOG")

if [ "$DRY_RUN" -eq 0 ]; then
    git add -A
    git commit -q -m "chore(release): v$VERSION"
    git tag -a "v$VERSION" -m "DialPilot v$VERSION"
    git push -q origin "$BRANCH" --follow-tags
    echo "    pushed $BRANCH + v$VERSION"
else
    echo "    [dry-run] git add -A && git commit && git tag -a v$VERSION && git push"
fi

if [ "$LOCAL_MODE" -eq 1 ]; then
    # ---------------------------------------------------------------- gh release
    step "GitHub release"
    NOTES_FILE="$PROJECT_DIR/.build/release-notes-$VERSION.md"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] gh release create v$VERSION $DMG $DMG.sha256"
    else
        printf '%s\n' "$NOTES" > "$NOTES_FILE"
        gh release create "v$VERSION" "$DMG" "$DMG.sha256" \
            --title "DialPilot v$VERSION" --notes-file "$NOTES_FILE"
    fi

    # ----------------------------------------------------------------------- tap
    step "Homebrew cask"
    run ./scripts/update-cask.sh --commit

    step "Done"
    cat <<DONE
    https://github.com/$REPO/releases/tag/v$VERSION
    brew update && brew upgrade --cask dialpilot
DONE
else
    step "CI takes over"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] gh run watch (release workflow triggered by the tag)"
    else
        # Give Actions a moment to register the run, then follow it.
        sleep 8
        RUN_ID=$(gh run list -R "$REPO" --workflow release.yml --limit 1 \
            --json databaseId --jq '.[0].databaseId')
        if [ -n "$RUN_ID" ]; then
            gh run watch "$RUN_ID" -R "$REPO" --exit-status || die "CI release failed — see the run log"
        else
            echo "    no run registered yet; watch: gh run watch -R $REPO"
        fi
    fi
    step "Done"
    cat <<DONE
    https://github.com/$REPO/releases/tag/v$VERSION
    brew update && brew upgrade --cask dialpilot
DONE
fi
