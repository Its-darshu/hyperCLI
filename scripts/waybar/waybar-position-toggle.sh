#!/usr/bin/env bash
# Toggle Waybar position between top and bottom.
# Maintains persistence across sessions and coordinates cleanly with waybar-autohide daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
pid_file="$runtime_dir/waybar-autohide.pid"
lock_file="$runtime_dir/waybar-position-toggle.lock"
waybar_config="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"
project_config="$REPO_DIR/waybar/config"

# Prevent concurrent toggle executions
exec 200>"$lock_file"
if ! flock -n 200; then
    exit 0
fi

# Clean up lock file descriptor on exit
cleanup() {
    flock -u 200 2>/dev/null || true
    exec 200>&- 2>/dev/null || true
    rm -f "$lock_file" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Determine current position from live config (fallback to project config)
config_source="$waybar_config"
[ ! -f "$config_source" ] && config_source="$project_config"

if grep -q '"position": *"top"' "$config_source" 2>/dev/null; then
    current_pos="top"
else
    current_pos="bottom"
fi

# Target position (support toggle, top, bottom)
mode="${1:-toggle}"
case "$mode" in
    top)
        new_pos="top"
        ;;
    bottom)
        new_pos="bottom"
        ;;
    toggle|*)
        if [ "$current_pos" = "top" ]; then
            new_pos="bottom"
        else
            new_pos="top"
        fi
        ;;
esac

# Update live config
if [ -f "$waybar_config" ]; then
    sed -i "s/\"position\": *\"$current_pos\"/\"position\": \"$new_pos\"/g" "$waybar_config"
fi

# Update project repository config if present
if [ -f "$project_config" ]; then
    sed -i "s/\"position\": *\"$current_pos\"/\"position\": \"$new_pos\"/g" "$project_config"
fi

# Terminate existing Waybar instance cleanly to avoid duplicate processes
pkill -x waybar 2>/dev/null || true
for i in {1..20}; do
    if ! pgrep -x waybar >/dev/null; then
        break
    fi
    sleep 0.05
done

# Force kill if still lingering
if pgrep -x waybar >/dev/null; then
    pkill -9 -x waybar 2>/dev/null || true
    sleep 0.05
fi

# Launch the new Waybar instance via Hyprland dispatch
hyprctl dispatch exec -- waybar

# Wait for Waybar to launch
for i in {1..20}; do
    if pgrep -x waybar >/dev/null; then
        break
    fi
    sleep 0.05
done

# Signal waybar-autohide daemon if running to sync position and visibility immediately
if [ -f "$pid_file" ]; then
    autohide_pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$autohide_pid" ] && kill -0 "$autohide_pid" 2>/dev/null; then
        kill -USR2 "$autohide_pid" 2>/dev/null || true
    fi
fi

# Show desktop notification
capitalized_pos="$(tr '[:lower:]' '[:upper:]' <<< "${new_pos:0:1}")${new_pos:1}"
if command -v dunstify >/dev/null 2>&1; then
    dunstify -a "Waybar" -i preferences-desktop-display "Waybar: $capitalized_pos" "Position set to $new_pos" -t 1500
elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Waybar" -i preferences-desktop-display "Waybar: $capitalized_pos" "Position set to $new_pos" -t 1500
fi
