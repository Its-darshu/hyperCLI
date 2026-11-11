#!/bin/bash
set -euo pipefail

echo "=== Hyprland Fedora Setup Script ==="
echo "Fedora 43+ optimized"
echo ""

# 1. Core and UI package definitions
PACKAGES=(
  hyprland
  hyprlock
  hyprpaper
  hypridle
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  waybar
  fuzzel
  gnome-terminal
  foot
  thunar
  thunar-volman
  dunst
  grim
  slurp
  wl-clipboard
  cliphist
  swappy
  jq
  cargo
  gtk4-devel
  gtk4-layer-shell
  gtk4-layer-shell-devel
  brightnessctl
  playerctl
  bluez
  blueman
  NetworkManager-tui
  network-manager-applet
  pipewire
  pipewire-pulse
  pipewire-alsa
  wireplumber
  jetbrains-mono-fonts
)

echo "[1/4] Checking installed packages..."
MISSING=()
for pkg in "${PACKAGES[@]}"; do
  if ! rpm -q "$pkg" &>/dev/null; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "  All core packages are already installed."
else
  echo "  Found ${#MISSING[@]} package(s) to install:"
  printf '    • %s\n' "${MISSING[@]}"
  echo ""

  # Prompt before installing unless -y is passed
  if [ "${1:-}" != "-y" ] && [ -t 0 ]; then
    read -r -p "Do you want to proceed with installing missing packages? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Installation aborted by user."
      exit 0
    fi
  fi

  echo "  Installing missing packages via dnf..."
  sudo dnf install -y "${MISSING[@]}"
fi

# 2. Optional tools check (wlogout, swww, polkit agent)
echo "[2/4] Checking optional packages..."
for opt in wlogout polkit-kde polkit-gnome swww; do
  if ! rpm -q "$opt" &>/dev/null; then
    echo "  Optional package '$opt' is not installed."
  fi
done

# 3. Audio service activation
echo "[3/4] Enabling user audio services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

# 4. Screenshots directory and GNOME Settings launchers
echo "[4/4] Setting up user directories and launchers..."
mkdir -p "$HOME/Pictures/screenshots"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
if [ -d "$REPO_DIR/local-apps" ]; then
  mkdir -p "$HOME/.local/share/applications"
  cp -f "$REPO_DIR"/local-apps/*.desktop "$HOME/.local/share/applications/"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  echo "  GNOME Settings + panels patched to launch under Hyprland"
fi

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Log out of your current session"
echo "  2. On the login screen, select 'Hyprland' as the session"
echo "     OR switch to TTY2 (Ctrl+Alt+F2), login, and type: Hyprland"
echo ""
echo "Key bindings cheatsheet:"
echo "  Super+Enter    → New terminal"
echo "  Super+Q        → Close window"
echo "  Super+A        → App launcher"
echo "  Super+1-9      → Switch workspace"
echo "  Super+P        → Power menu"
echo "  Super+L        → Lock screen"
echo "  Super+S        → Screenshot region"
