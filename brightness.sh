#!/usr/bin/env bash
# Adjust brightness and show a custom Dunst OSD progress bar.

case "$1" in
    up)
        brightnessctl set +5%
        ;;
    down)
        brightnessctl set 5%-
        ;;
esac

# Get current brightness percent
val=$(brightnessctl -m | cut -d, -f4 | tr -d '%')

dunstify -a "Brightness" -h string:x-dunst-stack-tag:brightness -h int:value:"$val" -i display-brightness "Brightness: ${val}%" -t 1500
