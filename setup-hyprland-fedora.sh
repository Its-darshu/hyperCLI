#!/bin/bash
set -e

echo "=== Hyprland Fedora Setup Script ==="
echo "Fedora 43+ optimized"
echo ""

# Add Hyprland COPR for packages not yet in main repos
echo "[1/6] Adding solopasha/hyprland COPR..."
sudo dnf copr enable -y solopasha/hyprland 2>/dev/null || echo "COPR already enabled or skipped"

# Core Hyprland compositor and ecosystem
echo "[2/6] Installing Hyprland core..."
sudo dnf install -y \
  hyprland \
  hyprlock \
  hyprpaper \
  hypridle \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk

# Status bar, app launcher, terminals
echo "[3/6] Installing UI tools..."
sudo dnf install -y \
  waybar \
  fuzzel \
  gnome-terminal \
  foot \
  thunar \
  thunar-volman

# Notifications, screenshots, clipboard
sudo dnf install -y \
  dunst \
  grim \
  slurp \
  wl-clipboard \
  cliphist \
  swappy

# System controls
sudo dnf install -y \
  brightnessctl \
  playerctl \
  bluez \
  blueman \
  NetworkManager-tui \
  network-manager-applet

# Wallpaper daemon
sudo dnf install -y swww 2>/dev/null || \
  sudo dnf install -y swww --enablerepo=copr:copr.fedorainfracloud.org:solopasha:hyprland 2>/dev/null || \
  echo "swww not found - install manually or use hyprpaper instead"

# Logout menu
sudo dnf install -y wlogout 2>/dev/null || echo "wlogout already installed or not in repos"

# Polkit auth agent (KDE)
sudo dnf install -y polkit-kde 2>/dev/null || \
  sudo dnf install -y polkit-gnome 2>/dev/null || \
  echo "Install polkit agent manually"

# Audio stack
echo "[4/6] Enabling audio (pipewire)..."
sudo dnf install -y \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  wireplumber
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

# Fonts
sudo dnf install -y \
  jetbrains-mono-fonts \
  nerd-fonts 2>/dev/null || \
  sudo dnf install -y jetbrains-mono-fonts 2>/dev/null || true

echo "[5/6] Creating Pictures directory for screenshots..."
mkdir -p ~/Pictures/screenshots

echo "[6/6] Installing GNOME Settings launcher fixes..."
# gnome-control-center refuses to start unless XDG_CURRENT_DESKTOP contains
# GNOME/Unity, so it does nothing when launched from a Hyprland menu. These
# override .desktop files inject XDG_CURRENT_DESKTOP=GNOME so Settings (and
# every panel) opens normally.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -d "$SCRIPT_DIR/local-apps" ]; then
  mkdir -p ~/.local/share/applications
  cp "$SCRIPT_DIR"/local-apps/*.desktop ~/.local/share/applications/
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  echo "  GNOME Settings + panels patched to launch under Hyprland"
else
  echo "  local-apps/ not found next to this script - skipping"
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
