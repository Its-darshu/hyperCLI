#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Videos/wallpapers"
STATE_FILE="$HOME/.config/hypr/current_wallpaper"

mkdir -p "$WALLPAPER_DIR" "$(dirname "$STATE_FILE")"

# Find video, gif, and static image files
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
    -iname "*.mp4" -o \
    -iname "*.webm" -o \
    -iname "*.mkv" -o \
    -iname "*.gif" -o \
    -iname "*.png" -o \
    -iname "*.jpg" -o \
    -iname "*.jpeg" -o \
    -iname "*.webp" \
\) | sort)

if [ ${#WALLPAPERS[@]} -eq 0 ]; then
    notify-send "Wallpaper Shifter" "No wallpaper files found in $WALLPAPER_DIR" -u critical
    exit 1
fi

is_on_battery() {
    for bat in /sys/class/power_supply/BAT*; do
        if [ -f "$bat/status" ]; then
            status=$(cat "$bat/status" 2>/dev/null)
            if [[ "$status" == "Discharging" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

set_wallpaper() {
    local target="$1"
    if [ ! -f "$target" ]; then
        notify-send "Wallpaper Shifter" "File not found: $target" -u critical
        exit 1
    fi

    # Save active state
    echo "$target" > "$STATE_FILE"

    # Terminate running mpvpaper instance
    killall -9 mpvpaper 2>/dev/null || true
    sleep 0.2

    # Determine mpv options based on power source
    local mpv_opts="no-audio loop hwdec=auto panscan=1.0"
    if is_on_battery; then
        # Battery optimization: cap playback to 24fps to save GPU/CPU cycles
        mpv_opts="$mpv_opts vf=fps=24"
    fi

    # Launch wallpaper
    nohup mpvpaper -o "$mpv_opts" '*' "$target" > /dev/null 2>&1 &

    # Send OS notification
    local name
    name=$(basename "$target")
    local bat_msg=""
    if is_on_battery; then
        bat_msg=" ⚡ (Battery Mode: 24fps)"
    fi
    notify-send "Wallpaper Changed" "Active wallpaper:\n<b>$name</b>$bat_msg" -i image-x-generic -r 9911
}

toggle_wallpaper() {
    if pgrep -x mpvpaper >/dev/null; then
        killall -9 mpvpaper 2>/dev/null || true
        notify-send "Live Wallpaper Paused" "Stopped rendering to save battery power" -i media-playback-pause -r 9911
    else
        if [ -f "$STATE_FILE" ] && [ -f "$(cat "$STATE_FILE")" ]; then
            set_wallpaper "$(cat "$STATE_FILE")"
        else
            set_wallpaper "${WALLPAPERS[0]}"
        fi
        notify-send "Live Wallpaper Resumed" "Rendering resumed" -i media-playback-start -r 9911
    fi
}

get_current_index() {
    local current=""
    [ -f "$STATE_FILE" ] && current=$(cat "$STATE_FILE")
    for i in "${!WALLPAPERS[@]}"; do
        if [[ "${WALLPAPERS[$i]}" == "$current" ]]; then
            echo "$i"
            return
        fi
    done
    echo "0"
}

action="${1:-next}"

case "$action" in
    next|shift)
        idx=$(get_current_index)
        next_idx=$(( (idx + 1) % ${#WALLPAPERS[@]} ))
        set_wallpaper "${WALLPAPERS[$next_idx]}"
        ;;
    prev)
        idx=$(get_current_index)
        prev_idx=$(( (idx - 1 + ${#WALLPAPERS[@]}) % ${#WALLPAPERS[@]} ))
        set_wallpaper "${WALLPAPERS[$prev_idx]}"
        ;;
    toggle|pause)
        toggle_wallpaper
        ;;
    select|menu)
        options=""
        current=""
        [ -f "$STATE_FILE" ] && current=$(cat "$STATE_FILE")

        for w in "${WALLPAPERS[@]}"; do
            base=$(basename "$w")
            if [[ "$w" == "$current" ]]; then
                options+="* $base\n"
            else
                options+="  $base\n"
            fi
        done

        selected=$(echo -e -n "$options" | fuzzel -d -p "Select Wallpaper: " --width 35 --lines 10)
        if [ -n "$selected" ]; then
            clean_name=$(echo "$selected" | sed 's/^[* ]*//')
            set_wallpaper "$WALLPAPER_DIR/$clean_name"
        fi
        ;;
    init|autostart)
        if [ -f "$STATE_FILE" ] && [ -f "$(cat "$STATE_FILE")" ]; then
            set_wallpaper "$(cat "$STATE_FILE")"
        else
            set_wallpaper "${WALLPAPERS[0]}"
        fi
        ;;
    *)
        if [ -f "$1" ]; then
            set_wallpaper "$1"
        else
            echo "Usage: $0 {next|prev|toggle|select|init|<file_path>}"
            exit 1
        fi
        ;;
esac
