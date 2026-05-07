#!/usr/bin/env bash
# Build Manifold as an AppImage.
# Requires: appimagetool on PATH (https://appimage.github.io/appimagetool/)
#
# Usage:
#   bash apps/desktop-flutter/tools/releaselinux-appimage.sh
#   bash apps/desktop-flutter/tools/releaselinux-appimage.sh --channel stable
#
# Produces: Manifold-<version>-x86_64.AppImage in the tools/ directory.
#
# Best practices followed (per docs.appimage.org):
#   - AppDir uses relative paths only (no hardcoded /usr)
#   - AppRun sets LD_LIBRARY_PATH relative to $HERE
#   - .desktop file validated format with proper Categories
#   - Icon at root AND in hicolor hierarchy
#   - Bundle contains all Flutter runtime libs (no host deps beyond glibc/GTK)
#   - No archive wrapping — raw .AppImage file for appimaged compatibility

set -euo pipefail

CHANNEL="beta"
BASE_URL="${MANIFOLD_UPDATE_BASE_URL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)  CHANNEL="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"

get_pubspec_version() {
  grep -m1 '^version:' "$FLUTTER_DIR/pubspec.yaml" | sed 's/version:\s*//;s/+.*//' | tr -d '[:space:]'
}

get_git_sha() {
  git -C "$FLUTTER_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo ""
}

VERSION="$(get_pubspec_version)"
SHA="$(get_git_sha)"

if ! command -v appimagetool &>/dev/null; then
  echo "appimagetool not found. Install from https://appimage.github.io/appimagetool/" >&2
  exit 1
fi

echo -e "\033[36m==> building manifold $VERSION ($CHANNEL)${SHA:+ $SHA}\033[0m"

DEFINES=(
  "--dart-define=MANIFOLD_CHANNEL=$CHANNEL"
  "--dart-define=MANIFOLD_VERSION=$VERSION"
)
[[ -n "$SHA" ]]      && DEFINES+=("--dart-define=MANIFOLD_GIT_SHA=$SHA")
[[ -n "$BASE_URL" ]] && DEFINES+=("--dart-define=MANIFOLD_UPDATE_BASE_URL=$BASE_URL")

cd "$FLUTTER_DIR"
flutter build linux --release "${DEFINES[@]}"

RELEASE_DIR="$FLUTTER_DIR/build/linux/x64/release/bundle"
APPDIR="$FLUTTER_DIR/build/Manifold.AppDir"

echo -e "\033[36m==> assembling AppDir\033[0m"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/64x64/apps"

# Copy the entire Flutter bundle — binary + lib/ + data/
cp -a "$RELEASE_DIR/." "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/git_desktop"

# AppRun — the entry point. Sets up library paths relative to the
# AppImage mount point so Flutter's bundled .so files are found
# before any system equivalents. GDK_BACKEND=x11 is a safe fallback
# that works on both X11 and XWayland; pure Wayland users can
# override with GDK_BACKEND=wayland.
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
SELF="$(readlink -f "$0")"
HERE="$(dirname "$SELF")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:${LD_LIBRARY_PATH:-}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export FLUTTER_ENGINE_SWITCH_SKIA="${FLUTTER_ENGINE_SWITCH_SKIA:-}"
exec "$HERE/usr/bin/git_desktop" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# .desktop file — validated format per freedesktop.org spec.
# Exec line uses just the binary name (AppImage handles path resolution).
# StartupWMClass must match the GTK application ID's last segment.
cat > "$APPDIR/manifold.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Manifold
GenericName=Git Client
Comment=Manifold Git Client
Exec=git_desktop
Icon=manifold
Terminal=false
Categories=Development;RevisionControl;
MimeType=x-scheme-handler/git;
StartupWMClass=git_desktop
Keywords=git;vcs;version;control;repository;
EOF
cp "$APPDIR/manifold.desktop" "$APPDIR/usr/share/applications/"

# Icon — place at AppDir root (required by appimagetool) AND in the
# hicolor icon theme hierarchy for proper desktop integration.
ICON_SRC="$RELEASE_DIR/data/flutter_assets/assets/icon.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APPDIR/manifold.png"
  cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/manifold.png"
  # Generate smaller sizes if ImageMagick is available
  if command -v convert &>/dev/null; then
    convert "$ICON_SRC" -resize 128x128 "$APPDIR/usr/share/icons/hicolor/128x128/apps/manifold.png"
    convert "$ICON_SRC" -resize 64x64 "$APPDIR/usr/share/icons/hicolor/64x64/apps/manifold.png"
  else
    cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/128x128/apps/manifold.png"
    cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/64x64/apps/manifold.png"
  fi
else
  echo "Warning: icon.png not found at $ICON_SRC — AppImage will have no icon" >&2
  # Create minimal valid PNG (1x1 transparent) so appimagetool doesn't fail
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$APPDIR/manifold.png"
fi

OUTPUT="$SCRIPT_DIR/Manifold-${VERSION}-x86_64.AppImage"

echo -e "\033[36m==> packaging AppImage\033[0m"
ARCH=x86_64 appimagetool "$APPDIR" "$OUTPUT"

echo -e "\033[32m==> done\033[0m"
echo "    channel  : $CHANNEL"
echo "    version  : $VERSION"
[[ -n "$SHA" ]] && echo "    sha      : $SHA"
echo "    appimage : $OUTPUT"
echo "    size     : $(du -h "$OUTPUT" | cut -f1)"
