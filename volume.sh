#!/usr/bin/env bash
# Adjust volume and show a custom Dunst OSD progress bar.

# Get current volume and mute state
get_volume() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

is_muted() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "\[MUTED\]"
}

case "$1" in
    up)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
        ;;
    down)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
esac

vol=$(get_volume)

if is_muted || [ "$vol" -eq 0 ]; then
    dunstify -a "Volume" -h string:x-dunst-stack-tag:volume -i audio-volume-muted "Muted" -t 1500
else
    # Show volume progress bar (using Dunst's built-in progress bar capability)
    dunstify -a "Volume" -h string:x-dunst-stack-tag:volume -h int:value:"$vol" -i audio-volume-high "Volume: ${vol}%" -t 1500
fi
