#!/usr/bin/env bash
# Deploy hyperCLI repository configurations and scripts into ~/.config/
# Safe to re-run at any time.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Deploying hyperCLI configuration..."

# 1. Hyprland configuration
mkdir -p "$HOME/.config/hypr/config"
cp -f "$REPO_DIR"/config/*.conf "$HOME/.config/hypr/config/"
cp -f "$REPO_DIR"/config/hyprland.conf "$HOME/.config/hypr/hyprland.conf"

# Replace any hardcoded home paths in AQ_DRM_DEVICES with current $HOME
for conf_target in "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/config/hyprland.conf"; do
    if [ -f "$conf_target" ]; then
        sed -i "s|/home/[^/]*/\.config/hypr|${HOME}/.config/hypr|g" "$conf_target"
    fi
done

# Ensure hardware DRM symlinks exist dynamically
if [ ! -e "$HOME/.config/hypr/intel-card" ]; then
    intel_pci=$(find /dev/dri/by-path/ -name "*:00:02.0-card" 2>/dev/null | head -n1)
    [ -n "$intel_pci" ] && ln -sf "$intel_pci" "$HOME/.config/hypr/intel-card"
fi
if [ ! -e "$HOME/.config/hypr/nvidia-card" ]; then
    nvidia_pci=$(find /dev/dri/by-path/ -name "*:01:00.0-card" 2>/dev/null | head -n1)
    [ -n "$nvidia_pci" ] && ln -sf "$nvidia_pci" "$HOME/.config/hypr/nvidia-card"
fi

# Provide top-level symlinks for backward compatibility
for conf in autostart.conf keybinds.conf rules.conf hypridle.conf hyprlock.conf; do
    ln -sf "config/$conf" "$HOME/.config/hypr/$conf"
done

# 2. Scripts (categorized directories)
mkdir -p "$HOME/.config/hypr/scripts"/{system,network,desktop,waybar,utilities}
cp -f "$REPO_DIR"/scripts/system/*.sh "$HOME/.config/hypr/scripts/system/"
cp -f "$REPO_DIR"/scripts/network/*.sh "$HOME/.config/hypr/scripts/network/"
cp -f "$REPO_DIR"/scripts/desktop/*.sh "$HOME/.config/hypr/scripts/desktop/"
cp -f "$REPO_DIR"/scripts/waybar/*.sh "$HOME/.config/hypr/scripts/waybar/"
cp -f "$REPO_DIR"/scripts/utilities/*.sh "$HOME/.config/hypr/scripts/utilities/"

# Top-level backward compatibility symlinks in scripts/
for category in system network desktop waybar utilities; do
    for script in "$HOME/.config/hypr/scripts/$category"/*.sh; do
        [ -f "$script" ] && ln -sf "$category/$(basename "$script")" "$HOME/.config/hypr/scripts/$(basename "$script")"
    done
done

# 3. Binaries
if [ -f "$REPO_DIR/target/release/window-switcher" ]; then
    cp -f "$REPO_DIR/target/release/window-switcher" "$HOME/.config/hypr/scripts/desktop/window-switcher"
    ln -sf "desktop/window-switcher" "$HOME/.config/hypr/scripts/window-switcher"
fi
if [ -f "$REPO_DIR/target/release/audio-switcher-popup" ]; then
    cp -f "$REPO_DIR/target/release/audio-switcher-popup" "$HOME/.config/hypr/scripts/waybar/audio-switcher-popup"
    ln -sf "waybar/audio-switcher-popup" "$HOME/.config/hypr/scripts/audio-switcher-popup"
fi

# Ensure all deployed scripts are executable
chmod -R +x "$HOME/.config/hypr/scripts"

# 4. Waybar and Wlogout
mkdir -p "$HOME/.config/waybar" "$HOME/.config/wlogout"
cp -f "$REPO_DIR"/waybar/* "$HOME/.config/waybar/"
cp -f "$REPO_DIR"/wlogout/* "$HOME/.config/wlogout/"

# 5. Shell configurations
mkdir -p "$HOME/.config/fastfetch" "$HOME/.config/fish/functions"
cp -f "$REPO_DIR/fastfetch/config.jsonc" "$HOME/.config/fastfetch/"
cp -f "$REPO_DIR/fish/config.fish" "$HOME/.config/fish/"
cp -f "$REPO_DIR/fish/functions"/*.fish "$HOME/.config/fish/functions/"
cp -f "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

echo "==> Deploy complete!"
