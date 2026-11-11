#!/usr/bin/env bash
# One-time installer and build script for the Alt+Tab window switcher and audio popup.
# Safe to re-run.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/3] Installing GTK4 layer-shell build dependencies (sudo)…"
sudo dnf install -y gtk4-devel gtk4-layer-shell gtk4-layer-shell-devel

echo "==> [2/3] Building window-switcher and audio-switcher-popup via Cargo…"
cargo build --release --manifest-path "$DIR/Cargo.toml"

echo "==> [3/3] Deploying binaries to ~/.config/hypr/scripts/…"
mkdir -p "$HOME/.config/hypr/scripts"
cp -f "$DIR/target/release/window-switcher" "$HOME/.config/hypr/scripts/window-switcher"
cp -f "$DIR/target/release/audio-switcher-popup" "$HOME/.config/hypr/scripts/audio-switcher-popup"
cp -f "$DIR/switcher.sh" "$HOME/.config/hypr/scripts/switcher.sh"
cp -f "$DIR/audio-switcher.sh" "$HOME/.config/hypr/scripts/audio-switcher.sh"
chmod +x "$HOME/.config/hypr/scripts/window-switcher" "$HOME/.config/hypr/scripts/audio-switcher-popup" "$HOME/.config/hypr/scripts/switcher.sh" "$HOME/.config/hypr/scripts/audio-switcher.sh"

echo "==> Restarting switcher daemon…"
pkill -f "window-switcher" 2>/dev/null || true
sleep 0.3
hyprctl dispatch exec -- "$HOME/.config/hypr/scripts/switcher.sh init"

echo "Done! Native Rust window-switcher and audio-switcher-popup deployed and running."
