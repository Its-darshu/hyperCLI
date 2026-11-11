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
        if pgrep -f "audio-switcher-popup" >/dev/null; then
            pkill -f "audio-switcher-popup"
            exit 0
        fi

        # 1. Look for native compiled Rust binary
        if [ -x "$DIR/audio-switcher-popup" ]; then
            exec "$DIR/audio-switcher-popup"
        elif [ -x "$DIR/target/release/audio-switcher-popup" ]; then
            exec "$DIR/target/release/audio-switcher-popup"
        elif [ -x "$HOME/.config/hypr/scripts/audio-switcher-popup" ]; then
            exec "$HOME/.config/hypr/scripts/audio-switcher-popup"
        elif [ -x "$HOME/Project/hyperland/target/release/audio-switcher-popup" ]; then
            exec "$HOME/Project/hyperland/target/release/audio-switcher-popup"
        elif [ -x "$HOME/Project/hyperland/audio-switcher-popup" ]; then
            exec "$HOME/Project/hyperland/audio-switcher-popup"
        fi

        # 2. Look for Python fallback script
        if [ -f "$DIR/audio-switcher-popup.py" ]; then
            exec python3 "$DIR/audio-switcher-popup.py"
        elif [ -f "$HOME/.config/hypr/scripts/audio-switcher-popup.py" ]; then
            exec python3 "$HOME/.config/hypr/scripts/audio-switcher-popup.py"
        elif [ -f "$HOME/Project/hyperland/audio-switcher-popup.py" ]; then
            exec python3 "$HOME/Project/hyperland/audio-switcher-popup.py"
        else
            echo "ERROR: audio-switcher-popup not found" >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {status|popup}"
        exit 1
        ;;
esac
