#!/usr/bin/env bash
# Reveal waybar when the cursor touches the screen edge (top or bottom); hide it otherwise.
# Supports pinning via /run/user/<uid>/waybar-pinned and position toggling.
#
# Uses PID tracking to detect waybar restarts and resync state.

reveal_margin=20    # reveal when cursor is within this many px of the bottom edge
hide_margin=80      # hide when cursor moves above this many px from the bottom
poll=0.12           # seconds between cursor checks
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
pinned_file="$runtime_dir/waybar-pinned"
pid_file="$runtime_dir/waybar-autohide.pid"

# Save PID for signaling and clean up on exit
echo $$ > "$pid_file"
cleanup() {
    rm -f "$pid_file"
    exit 0
}
trap cleanup INT TERM
trap 'rm -f "$pid_file"' EXIT

screen_height() {
    hyprctl monitors -j 2>/dev/null \
        | jq -r 'first(.[] | select(.focused)) // .[0] | (.height / .scale) | floor'
}

get_position() {
    if grep -q '"position": *"top"' "$HOME/.config/waybar/config" 2>/dev/null; then
        echo "top"
    else
        echo "bottom"
    fi
}

pkill -x waybar 2>/dev/null
sleep 0.3
waybar &
until pgrep -x waybar >/dev/null; do sleep 0.2; done
sleep 0.2

# Set initial visibility state based on Waybar configuration
if grep -q '"start_hidden": true' "$HOME/.config/waybar/config" 2>/dev/null; then
    visible=0
else
    visible=1
fi

last_pid=$(pgrep -x waybar | head -1)
sh=$(screen_height)
pos_mode=$(get_position)
pid_check_counter=0

# Handle USR2 signal to instantly apply pin or position state
forced_check=0
trap "forced_check=1" USR2

while true; do
    if [ "$forced_check" -eq 0 ]; then
        sleep "$poll"
    else
        forced_check=0
        pos_mode=$(get_position)
    fi

    # Verify Waybar is running without spawning subshells/processes every 120ms.
    # kill -0 is a fast shell builtin syscall.
    if ! kill -0 "$last_pid" 2>/dev/null; then
        cur_pid=$(pgrep -x waybar 2>/dev/null | head -n 1)
        if [ -z "$cur_pid" ]; then
            nohup waybar >/dev/null 2>&1 &
            sleep 0.5
            cur_pid=$(pgrep -x waybar 2>/dev/null | head -n 1)
            [ -z "$cur_pid" ] && continue
        fi

        # Waybar restarted — sync state variables with actual config value
        sleep 0.5
        if grep -q '"start_hidden": true' "$HOME/.config/waybar/config" 2>/dev/null; then
            visible=0
        else
            visible=1
        fi
        pos_mode=$(get_position)
        last_pid="$cur_pid"
        continue
    fi

    # Pinned state check
    if [ -f "$pinned_file" ]; then
        # If pinned and somehow hidden, reveal it
        if [ "$visible" -eq 0 ]; then
            pkill -SIGUSR1 -x waybar && visible=1
        fi
        continue
    fi

    # Parse cursorpos directly in Bash without spawning jq
    pos=$(hyprctl cursorpos 2>/dev/null)
    y="${pos#*, }"
    [ -z "$y" ] && continue
    [ -z "$sh" ] && sh=$(screen_height) && [ -z "$sh" ] && continue

    if [ "$pos_mode" = "top" ]; then
        if [ "$visible" -eq 0 ] && [ "$y" -le "$reveal_margin" ]; then
            pkill -SIGUSR1 -x waybar && visible=1
        elif [ "$visible" -eq 1 ] && [ "$y" -ge "$hide_margin" ]; then
            # Only hide if NOT pinned (extra check for safety)
            if [ ! -f "$pinned_file" ]; then
                pkill -SIGUSR1 -x waybar && visible=0
            fi
        fi
    else
        reveal_at=$((sh - reveal_margin))
        hide_at=$((sh - hide_margin))

        if [ "$visible" -eq 0 ] && [ "$y" -ge "$reveal_at" ]; then
            pkill -SIGUSR1 -x waybar && visible=1
        elif [ "$visible" -eq 1 ] && [ "$y" -le "$hide_at" ]; then
            # Only hide if NOT pinned (extra check for safety)
            if [ ! -f "$pinned_file" ]; then
                pkill -SIGUSR1 -x waybar && visible=0
            fi
        fi
    fi
done
