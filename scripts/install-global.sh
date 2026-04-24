#!/usr/bin/env bash
# Installs Thumbz to ~/Applications and a `thumbz` launcher into /opt/homebrew/bin.
# Run from repo root:  ./scripts/install-global.sh
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
INSTALL_APP="$HOME/Applications/Thumbz.app"
LAUNCHER="/opt/homebrew/bin/thumbz"

# Locate the built app. When run as an Xcode post-build phase, these env vars are set
# by Xcode itself and point at the fresh output. Fall back to the xcodebuild CLI path.
if [[ -n "${BUILT_PRODUCTS_DIR:-}" && -n "${FULL_PRODUCT_NAME:-}" ]]; then
    BUILT_APP="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
elif [[ -d "$ROOT/build/Build/Products/Debug/Thumbz.app" ]]; then
    BUILT_APP="$ROOT/build/Build/Products/Debug/Thumbz.app"
else
    # Try DerivedData (default Xcode IDE location) as a last resort.
    BUILT_APP="$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Thumbz-"*/Build/Products/Debug/Thumbz.app 2>/dev/null | head -1)"
fi

if [[ -z "$BUILT_APP" || ! -d "$BUILT_APP" ]]; then
    echo "No built Thumbz.app found. Run: xcodebuild -project Thumbz.xcodeproj -scheme Thumbz" >&2
    exit 1
fi

# Only reinstall on Debug (don't mess up Release / Archive flows).
CFG="${CONFIGURATION:-Debug}"
if [[ "$CFG" != "Debug" ]]; then
    echo "Skipping install (CONFIGURATION=$CFG)"
    exit 0
fi

mkdir -p "$HOME/Applications"
echo "→ Copying $BUILT_APP → $INSTALL_APP"
rm -rf "$INSTALL_APP"
cp -R "$BUILT_APP" "$INSTALL_APP"

# Remove quarantine so double-click launches without Gatekeeper prompt.
xattr -dr com.apple.quarantine "$INSTALL_APP" 2>/dev/null || true

# Re-sign ad-hoc so LaunchServices is happy after copy.
codesign --force --deep --sign - "$INSTALL_APP" 2>/dev/null || true

# Register with LaunchServices so `.thumbz` UTI is picked up.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f -R "$INSTALL_APP" >/dev/null 2>&1 || true

# Launcher script — forwards any args (files / urls) to the installed .app.
cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
# Launcher for Thumbz.app. Any args are passed as files to open.
APP="$HOME/Applications/Thumbz.app"
if [[ ! -d "$APP" ]]; then
    echo "Thumbz is not installed at $APP. Run install-global.sh from the repo." >&2
    exit 1
fi
if [[ $# -eq 0 ]]; then
    exec open -a "$APP"
else
    args=()
    for a in "$@"; do
        if [[ -e "$a" ]]; then
            args+=( "$(cd "$(dirname "$a")" && pwd)/$(basename "$a")" )
        else
            args+=( "$a" )
        fi
    done
    exec open -a "$APP" "${args[@]}"
fi
EOF
chmod +x "$LAUNCHER"

echo "✓ Installed: $INSTALL_APP"
echo "✓ Launcher:  $LAUNCHER"
echo
echo "Run:   thumbz                 # launches the app"
echo "Run:   thumbz some.thumbz     # opens a project file"
echo "Run:   thumbz image.webp      # places an image as a Smart Object"
