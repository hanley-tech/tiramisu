#!/usr/bin/env bash
# release.sh — build, sign, notarize, package, publish a Tiramisu DMG.
#
# Usage:
#   scripts/release.sh v0.1.0
#   scripts/release.sh v0.1.0 --no-sign --no-notarize  # unsigned dev build
#   scripts/release.sh v0.1.0 --no-mirror              # skip Lightsail rsync
#   scripts/release.sh v0.1.0 --draft                  # GitHub Release as draft
#
# Requires (all enforced by the pre-flight check below):
#   - macOS 26 SDK (Xcode 17+)
#   - xcodegen, create-dmg
#   - gh CLI signed in to hanley-tech
#   - "Developer ID Application: Hanley Tze Ho Leung (FG5Y9SD7U6)" in keychain
#   - notarytool profile "tiramisu-notary" stored in keychain. One-time:
#       xcrun notarytool store-credentials "tiramisu-notary" \
#         --apple-id <your apple id email> \
#         --team-id  FG5Y9SD7U6 \
#         --password <app-specific-password from appleid.apple.com>
#   - SSH key for the Lightsail mirror at ~/.ssh/lightsail-hanley-world.pem
#
# What happens:
#   1. Pre-flight (clean tree, tag exists, tools available)
#   2. xcodegen + xcodebuild archive (Release config, macOS 26 SDK)
#   3. Export the .app from the .xcarchive
#   4. Codesign the .app (Developer ID + hardened runtime + timestamp)
#   5. Notarize + staple the .app (so a user who extracts the .app
#      standalone still gets a silent first launch — DMG-level staple
#      doesn't help if the .app leaves the DMG)
#   6. create-dmg with branded volume + app-drop link
#   7. Codesign the DMG itself (notarization requires a signed artifact)
#   8. Notarize + staple the DMG (so the DMG mount is silent too —
#      without DMG staple, Gatekeeper prompts on the *first mount* even
#      if the .app inside is fine)
#   9. gh release create + upload DMG asset
#  10. rsync DMG to /var/www/tiramisu.hanley.world/download/ — both a
#      version-pinned filename and a Tiramisu.dmg "latest" symlink.

set -euo pipefail

# ── flags / defaults ─────────────────────────────────────────────────
DO_SIGN=1
DO_NOTARIZE=1
DO_MIRROR=1
DO_DRAFT=0
TAG=""
for arg in "$@"; do
    case "$arg" in
        --no-sign)     DO_SIGN=0; DO_NOTARIZE=0 ;;  # notarize requires signing
        --no-notarize) DO_NOTARIZE=0 ;;
        --no-mirror)   DO_MIRROR=0 ;;
        --draft)       DO_DRAFT=1 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0 ;;
        v*)            TAG="$arg" ;;
        *)
            echo "unknown flag: $arg  (run with --help)" >&2
            exit 2 ;;
    esac
done

if [[ -z "$TAG" ]]; then
    echo "usage: $0 v<X.Y.Z> [--no-sign] [--no-notarize] [--no-mirror] [--draft]" >&2
    exit 2
fi

# ── constants ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

DEV_ID="Developer ID Application: Hanley Tze Ho Leung (FG5Y9SD7U6)"
TEAM_ID="FG5Y9SD7U6"
NOTARY_PROFILE="tiramisu-notary"
GH_REPO="hanley-tech/tiramisu"
MIRROR_SSH="ubuntu@34.212.8.221"
MIRROR_KEY="$HOME/.ssh/lightsail-hanley-world.pem"
MIRROR_DIR="/var/www/tiramisu.hanley.world/download"

VERSION="${TAG#v}"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Tiramisu.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Tiramisu.app"
DMG_NAME="Tiramisu-$TAG.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# ── helpers ──────────────────────────────────────────────────────────
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. pre-flight ────────────────────────────────────────────────────
step "1/10 pre-flight checks"

# Clean working tree
if [[ -n "$(git status --porcelain)" ]]; then
    fail "working tree dirty. Commit or stash first."
fi

# Tag exists locally
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    fail "git tag $TAG doesn't exist. Create it first:  git tag -a $TAG -m '$TAG'"
fi

# HEAD == tag
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "$TAG")" ]]; then
    fail "HEAD is not on $TAG. Check out the tag first."
fi

# Required tools
for cmd in xcodegen xcodebuild create-dmg gh; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not on PATH"
done

# Cert in keychain (only if signing)
if [[ "$DO_SIGN" -eq 1 ]]; then
    if ! security find-identity -v -p codesigning | grep -q "$DEV_ID"; then
        fail "Developer ID cert not in keychain: $DEV_ID"
    fi
fi

# notarytool profile (only if notarizing)
if [[ "$DO_NOTARIZE" -eq 1 ]]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        fail "notarytool profile '$NOTARY_PROFILE' not set up. See header comment for one-time setup."
    fi
fi

# Mirror key (only if mirroring)
if [[ "$DO_MIRROR" -eq 1 ]]; then
    [[ -f "$MIRROR_KEY" ]] || fail "Lightsail SSH key not at $MIRROR_KEY"
fi

ok "pre-flight passed (tag=$TAG, sign=$DO_SIGN, notarize=$DO_NOTARIZE, mirror=$DO_MIRROR)"

# Clean previous build output
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ── 2. archive ───────────────────────────────────────────────────────
step "2/10 xcodegen + xcodebuild archive (Release)"
xcodegen generate >/dev/null
xcodebuild \
    -project Tiramisu.xcodeproj \
    -scheme Tiramisu \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive 2>&1 | tail -3

[[ -d "$ARCHIVE_PATH" ]] || fail "archive failed — no .xcarchive at $ARCHIVE_PATH"
ok "archive built"

# ── 3. export .app ───────────────────────────────────────────────────
step "3/10 export Tiramisu.app from archive"
# Copy the .app out of the .xcarchive. We don't use xcodebuild -exportArchive
# because it requires a manual ExportOptions.plist + provisioning profile dance
# that we don't need for Developer ID signing — the .app inside the archive
# is already the same binary we ship.
cp -R "$ARCHIVE_PATH/Products/Applications/Tiramisu.app" "$EXPORT_DIR/"
[[ -d "$APP_PATH" ]] || fail "expected $APP_PATH after copy"
ok "Tiramisu.app exported to $EXPORT_DIR/"

# ── 4. codesign ──────────────────────────────────────────────────────
if [[ "$DO_SIGN" -eq 1 ]]; then
    step "4/10 codesign with Developer ID + hardened runtime + timestamp"
    # --deep is deprecated for new code but fine here; we have a flat app with
    # no nested helpers. --options runtime is required for notarization.
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEV_ID" \
        "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -3
    ok "Tiramisu.app signed"
else
    step "4/10 codesign — SKIPPED (--no-sign)"
    warn "DMG will be unsigned. Users will need right-click → Open to bypass Gatekeeper."
fi

# ── 5. notarize ──────────────────────────────────────────────────────
if [[ "$DO_NOTARIZE" -eq 1 ]]; then
    step "5/10 notarize via Apple's service (this can take 1-5 min)"
    # notarytool needs a zip — we make it from the .app, then staple the
    # notarization back to the .app afterwards.
    NOTARY_ZIP="$BUILD_DIR/Tiramisu-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    rm -f "$NOTARY_ZIP"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH" 2>&1 | tail -2
    ok "notarization stapled to Tiramisu.app"
else
    step "5/10 notarize — SKIPPED (--no-notarize)"
fi

# ── 6. DMG ───────────────────────────────────────────────────────────
step "6/10 create-dmg"
# Use a clean staging folder so create-dmg doesn't sweep up build artifacts.
DMG_STAGE="$BUILD_DIR/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"

create-dmg \
    --volname "Tiramisu $TAG" \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "Tiramisu.app" 140 180 \
    --app-drop-link 400 180 \
    --hide-extension "Tiramisu.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_STAGE/" 2>&1 | tail -3

[[ -f "$DMG_PATH" ]] || fail "create-dmg produced no DMG at $DMG_PATH"
DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
ok "DMG built: $DMG_PATH ($DMG_SIZE)"

# ── 7. codesign the DMG ──────────────────────────────────────────────
if [[ "$DO_SIGN" -eq 1 ]]; then
    step "7/10 codesign the DMG"
    # Apple's modern advice: sign the outer container too. Without a
    # signed DMG, the .app inside is fine but the DMG itself triggers
    # Gatekeeper prompts on the first mount. --timestamp is required
    # for notarization eligibility.
    codesign --force --sign "$DEV_ID" --timestamp "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH" 2>&1 | tail -2
    ok "DMG signed"
else
    step "7/10 codesign DMG — SKIPPED (--no-sign)"
fi

# ── 8. notarize the DMG ──────────────────────────────────────────────
if [[ "$DO_NOTARIZE" -eq 1 ]]; then
    step "8/10 notarize the DMG (silent first-mount)"
    # The DMG itself goes through notarization. After this completes,
    # both the DMG mount AND the .app launch will be silent for users:
    #   - DMG mount → Gatekeeper sees the DMG's stapled ticket, OK
    #   - .app launch → Gatekeeper sees the .app's stapled ticket, OK
    # No internet required at first launch since both tickets are stapled.
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH" 2>&1 | tail -2
    # spctl is the actual Gatekeeper check end-users will hit. If this
    # passes here, it'll pass on their machines too.
    spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 | tail -2
    ok "DMG notarized + stapled — both DMG mount and .app launch are silent"
else
    step "8/10 notarize DMG — SKIPPED (--no-notarize)"
fi

# ── 9. GitHub Release ────────────────────────────────────────────────
step "9/10 publish to GitHub Releases"
RELEASE_FLAGS=(--repo "$GH_REPO" --title "Tiramisu $TAG")
[[ "$DO_DRAFT" -eq 1 ]] && RELEASE_FLAGS+=(--draft)

# Auto-generate notes from the previous tag's commits if a CHANGELOG.md
# isn't present.
if [[ -f CHANGELOG.md ]]; then
    RELEASE_FLAGS+=(--notes-file CHANGELOG.md)
else
    RELEASE_FLAGS+=(--generate-notes)
fi

# If a release for this tag already exists, upload the DMG to it instead of
# erroring. Useful when re-running after fixing something post-release.
if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    warn "Release $TAG already exists — uploading DMG to it (clobber)."
    gh release upload "$TAG" "$DMG_PATH" --repo "$GH_REPO" --clobber
else
    gh release create "$TAG" "$DMG_PATH" "${RELEASE_FLAGS[@]}"
fi
ok "GitHub Release published: https://github.com/$GH_REPO/releases/tag/$TAG"

# ── 10. mirror to Lightsail ──────────────────────────────────────────
if [[ "$DO_MIRROR" -eq 1 ]]; then
    step "10/10 mirror DMG to tiramisu.hanley.world/download/"
    # Push two paths:
    #   /download/Tiramisu-vX.Y.Z.dmg — version-specific archive
    #   /download/Tiramisu.dmg        — alias of latest, for the homepage button
    ssh -i "$MIRROR_KEY" "$MIRROR_SSH" "mkdir -p $MIRROR_DIR" 2>/dev/null
    rsync -avz -e "ssh -i $MIRROR_KEY" \
        "$DMG_PATH" "$MIRROR_SSH:$MIRROR_DIR/$DMG_NAME"
    # Symlink "latest" so https://tiramisu.hanley.world/download/Tiramisu.dmg
    # always serves the most recent version.
    ssh -i "$MIRROR_KEY" "$MIRROR_SSH" \
        "cd $MIRROR_DIR && ln -sf $DMG_NAME Tiramisu.dmg"
    ok "mirrored to https://tiramisu.hanley.world/download/$DMG_NAME"
    ok "homepage link: https://tiramisu.hanley.world/download/Tiramisu.dmg"
else
    step "10/10 Lightsail mirror — SKIPPED (--no-mirror)"
fi

# ── done ─────────────────────────────────────────────────────────────
echo
ok "Release complete: $TAG"
echo
echo "  GitHub:    https://github.com/$GH_REPO/releases/tag/$TAG"
echo "  Direct:    https://tiramisu.hanley.world/download/$DMG_NAME"
echo "  Latest:    https://tiramisu.hanley.world/download/Tiramisu.dmg"
echo "  Local DMG: $DMG_PATH"
