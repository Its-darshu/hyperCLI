#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Videos/wallpapers"
STATE_FILE="$HOME/.config/hypr/current_wallpaper"

mkdir -p "$WALLPAPER_DIR" "$(dirname "$STATE_FILE")"

# Find video, gif, and static image files (ignoring temp source files)
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
    -iname "*.mp4" -o \
    -iname "*.webm" -o \
    -iname "*.mkv" -o \
    -iname "*.gif" -o \
    -iname "*.png" -o \
    -iname "*.jpg" -o \
    -iname "*.jpeg" -o \
    -iname "*.webp" \
\) ! -name "source_4k_*" | sort)

if [ ${#WALLPAPERS[@]} -eq 0 ]; then
    notify-send "Wallpaper Shifter" "No wallpaper files found in $WALLPAPER_DIR" -u critical
    exit 1
fi

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

    # Launch 4K wallpaper with full screen fill (--keepaspect=no) and hardware decoding
    nohup mpvpaper -o "no-audio loop hwdec=auto --keepaspect=no" '*' "$target" > /dev/null 2>&1 &

    # Send OS notification
    local name
    name=$(basename "$target")
    notify-send "Wallpaper Changed" "Active wallpaper:\n<b>$name</b> (4K Full Screen)" -i image-x-generic -r 9911
}

toggle_wallpaper() {
    if pgrep -x mpvpaper >/dev/null; then
        killall -9 mpvpaper 2>/dev/null || true
        notify-send "Live Wallpaper Paused" "Wallpaper rendering paused" -i media-playback-pause -r 9911
    else
        if [ -f "$STATE_FILE" ] && [ -f "$(cat "$STATE_FILE")" ]; then
            set_wallpaper "$(cat "$STATE_FILE")"
        else
            set_wallpaper "${WALLPAPERS[0]}"
        fi
        notify-send "Live Wallpaper Resumed" "Wallpaper rendering resumed" -i media-playback-start -r 9911
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
