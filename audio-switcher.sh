#!/usr/bin/env bash
# Audio Output Switcher helper for Waybar
# Provides JSON status updates and toggles the GTK device selector popup

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$1" in
    status)
        def=$(pactl get-default-sink 2>/dev/null)
        if [[ "$def" == *"bluez"* ]]; then
            icon="󰥰"
            cls="bluetooth"
            label="Bluetooth Audio"
        elif [[ "$def" == *"Headphone"* ]]; then
            icon="󰋋"
            cls="headphones"
            label="Wired Headphones"
        elif [[ "$def" == *"Speaker"* ]]; then
            icon="󰓃"
            cls="speaker"
            label="Internal Speakers"
        elif [[ "$def" == *"HDMI"* || "$def" == *"DisplayPort"* ]]; then
            icon="󰍹"
            cls="hdmi"
            label="HDMI Display"
        else
            icon="󰓃"
            cls="audio"
            label="Audio Output"
        fi
        printf '{"text":"%s 󰅀","tooltip":"Audio Output: %s\\nClick to switch output","class":"%s"}\n' "$icon" "$label" "$cls"
        ;;
    popup)
        if pgrep -f "audio-switcher-popup.py" >/dev/null; then
            pkill -f "audio-switcher-popup.py"
            exit 0
        fi
        exec python3 "$DIR/audio-switcher-popup.py"
        ;;
    *)
        echo "Usage: $0 {status|popup}"
        exit 1
        ;;
esac
