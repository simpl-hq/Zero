#!/usr/bin/env bash
set -euo pipefail

# Zero Linux Installer — minimalist monochrome CLI setup for Debian/Ubuntu/AppImage

BOLD='\033[1m'
DIM='\033[2m'
WHITE='\033[97m'
GRAY='\033[90m'
RESET='\033[0m'

ARCH="$(uname -m)"
VERSION="${ZERO_VERSION:-1.0.0}"
MODE="auto"
LOCAL_PKG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deb) MODE="deb"; shift ;;
    --appimage) MODE="appimage"; shift ;;
    --file) LOCAL_PKG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

draw_header() {
  clear 2>/dev/null || true
  printf "\n"
  printf "${GRAY}┌────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${GRAY}│${RESET}  ${BOLD}${WHITE}Zero${RESET}  ${GRAY}v%s · %s${RESET}%*s${GRAY}│${RESET}\n" "$VERSION" "$ARCH" $((39 - ${#VERSION} - ${#ARCH})) ""
  printf "${GRAY}│${RESET}  ${DIM}Privacy Should Be Effortless.${RESET}                         ${GRAY}│${RESET}\n"
  printf "${GRAY}└────────────────────────────────────────────────────────┘${RESET}\n\n"
}

step_bar() {
  local pct="$1"
  local msg="$2"
  local filled=$((pct / 5))
  local empty=$((20 - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}━"; done
  for ((i=0; i<empty; i++)); do bar="${bar}─"; done
  printf "\r  ${WHITE}[%s]${RESET} ${GRAY}%3d%%${RESET}  %s\033[K" "$bar" "$pct" "$msg"
}

draw_header

if [[ "$MODE" == "auto" ]]; then
  if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    MODE="deb"
  else
    MODE="appimage"
  fi
fi

if [[ "$MODE" == "deb" ]]; then
  PKG_FILE="$LOCAL_PKG"
  if [[ -z "$PKG_FILE" ]]; then
    step_bar 20 "Resolving Zero .deb package (${ARCH})..."
    URL="https://github.com/simpl-hq/zero/releases/download/v${VERSION}/zero-desktop-ubuntu-24_04-${ARCH}.deb"
    PKG_FILE="/tmp/zero-${VERSION}-${ARCH}.deb"
    curl -fsSL "$URL" -o "$PKG_FILE"
  fi
  step_bar 65 "Installing Zero via dpkg..."
  sudo dpkg -i "$PKG_FILE" >/dev/null 2>&1 || sudo apt-get install -f -y >/dev/null 2>&1
  step_bar 95 "Updating desktop handlers..."
  command -v update-desktop-database >/dev/null 2>&1 && sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  step_bar 100 "Zero is installed."
  printf "\n\n  ${WHITE}Launch:${RESET} ${GRAY}zero${RESET}  (or open ${WHITE}Zero${RESET} from your Applications menu)\n\n"
else
  BIN_DIR="${HOME}/.local/bin"
  APP_DIR="${HOME}/.local/share/applications"
  mkdir -p "$BIN_DIR" "$APP_DIR"
  TARGET="$BIN_DIR/Zero.AppImage"

  if [[ -n "$LOCAL_PKG" ]]; then
    step_bar 45 "Copying AppImage..."
    cp "$LOCAL_PKG" "$TARGET"
  else
    step_bar 25 "Downloading Zero.AppImage (${ARCH})..."
    URL="https://github.com/simpl-hq/zero/releases/download/v${VERSION}/zero-desktop-${ARCH}.AppImage"
    curl -fsSL "$URL" -o "$TARGET"
  fi

  chmod +x "$TARGET"
  step_bar 80 "Registering desktop entry & zero:// URI handler..."
  cat > "$APP_DIR/app.zero.chat.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Zero
GenericName=Encrypted Messenger
Comment=Private and secure post-quantum messenger — zero user identifiers
Exec=${TARGET} %u
Icon=zero
Terminal=false
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/zero;
StartupWMClass=app-zero-core-desktop-MainKt
EOF
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  step_bar 100 "Zero is ready."
  printf "\n\n  ${WHITE}Launch:${RESET} ${GRAY}%s${RESET}\n\n" "$TARGET"
fi
