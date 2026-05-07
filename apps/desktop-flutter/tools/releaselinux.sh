#!/usr/bin/env bash
# Manifold release for Linux: build + stage to ~/Manifold + create .desktop entry.
# Mirrors release.ps1 for Windows.
#
# Usage:
#   bash apps/desktop-flutter/tools/releaselinux.sh
#   bash apps/desktop-flutter/tools/releaselinux.sh --channel stable
#
# --channel : dev | beta | stable   (default: beta)
# --base-url: update manifest base  (overrides MANIFOLD_UPDATE_BASE_URL env)

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
INSTALL_DIR="$HOME/Manifold"
EXE_NAME="git_desktop"

get_pubspec_version() {
  grep -m1 '^version:' "$FLUTTER_DIR/pubspec.yaml" | sed 's/version:\s*//;s/+.*//' | tr -d '[:space:]'
}

get_git_sha() {
  git -C "$FLUTTER_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo ""
}

VERSION="$(get_pubspec_version)"
SHA="$(get_git_sha)"

echo -e "\033[36m==> manifold $VERSION ($CHANNEL)${SHA:+ $SHA}\033[0m"

# Kill running instances so staging can overwrite
if pgrep -x "$EXE_NAME" >/dev/null 2>&1; then
  echo -e "\033[36m==> closing running Manifold instance(s)\033[0m"
  pkill -x "$EXE_NAME" || true
  sleep 0.5
fi

DEFINES=(
  "--dart-define=MANIFOLD_CHANNEL=$CHANNEL"
  "--dart-define=MANIFOLD_VERSION=$VERSION"
)
[[ -n "$SHA" ]]      && DEFINES+=("--dart-define=MANIFOLD_GIT_SHA=$SHA")
[[ -n "$BASE_URL" ]] && DEFINES+=("--dart-define=MANIFOLD_UPDATE_BASE_URL=$BASE_URL")

cd "$FLUTTER_DIR"

echo -e "\033[36m==> flutter build linux --release ${DEFINES[*]}\033[0m"
flutter build linux --release "${DEFINES[@]}"

RELEASE_DIR="$FLUTTER_DIR/build/linux/x64/release/bundle"
if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Release output missing: $RELEASE_DIR" >&2
  exit 1
fi

echo -e "\033[36m==> staging $INSTALL_DIR\033[0m"
mkdir -p "$INSTALL_DIR"
rsync -a --delete "$RELEASE_DIR/" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$EXE_NAME"

# .desktop entry for app launchers
DESKTOP_FILE="$HOME/.local/share/applications/manifold.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Manifold
Comment=Manifold Git Client ($CHANNEL $VERSION)
Exec=$INSTALL_DIR/$EXE_NAME
Icon=$INSTALL_DIR/data/flutter_assets/assets/icon.png
Terminal=false
Categories=Development;
StartupWMClass=git_desktop
EOF

echo -e "\033[32m==> done\033[0m"
echo "    channel : $CHANNEL"
echo "    version : $VERSION"
[[ -n "$SHA" ]] && echo "    sha     : $SHA"
echo "    exe     : $INSTALL_DIR/$EXE_NAME"
echo "    desktop : $DESKTOP_FILE"
