#!/usr/bin/env bash
# Toggle Waybar autohide pinning and exclusive space.

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
pinned_file="$runtime_dir/waybar-pinned"
pid_file="$runtime_dir/waybar-autohide.pid"
waybar_config="$HOME/.config/waybar/config"
project_config="$HOME/Project/hyperland/waybar/config"

if [ -f "$pinned_file" ]; then
    rm -f "$pinned_file"
    # Switch to non-exclusive zone and start hidden for autohide overlay
    sed -i 's/exclusive": true/exclusive": false/g' "$waybar_config"
    sed -i 's/start_hidden": false/start_hidden": true/g' "$waybar_config"
    if [ -f "$project_config" ]; then
        sed -i 's/exclusive": true/exclusive": false/g' "$project_config"
        sed -i 's/start_hidden": false/start_hidden": true/g' "$project_config"
    fi
    dunstify -a "Waybar" -i display-brightness "Waybar Autohide: Enabled" -t 1500
else
    touch "$pinned_file"
    # Switch to exclusive zone and start visible so windows don't overlap waybar
    sed -i 's/exclusive": false/exclusive": true/g' "$waybar_config"
    sed -i 's/start_hidden": true/start_hidden": false/g' "$waybar_config"
    if [ -f "$project_config" ]; then
        sed -i 's/exclusive": false/exclusive": true/g' "$project_config"
        sed -i 's/start_hidden": true/start_hidden": false/g' "$project_config"
    fi
    dunstify -a "Waybar" -i display-brightness "Waybar Pinned: Sticky" -t 1500
fi

# Send SIGUSR2 to waybar-autohide.sh to immediately apply the change!
if [ -f "$pid_file" ]; then
    kill -USR2 "$(cat "$pid_file")" 2>/dev/null || true
fi

# Restart waybar to apply exclusive zone setting
pkill -x waybar
sleep 0.3
waybar >/dev/null 2>&1 &
