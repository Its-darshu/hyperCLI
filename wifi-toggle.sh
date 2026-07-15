#!/usr/bin/env bash
# wifi-toggle.sh — WiFi toggle / connection-editor launcher for Waybar
# Usage:
#   wifi-toggle.sh          → open nm-connection-editor (left-click)
#   wifi-toggle.sh editor   → open nm-connection-editor (left-click)
#   wifi-toggle.sh toggle   → toggle WiFi radio on/off  (right-click)

case "${1:-editor}" in
    toggle)
        # Read current WiFi radio state from NetworkManager
        status="$(nmcli radio wifi)"
        if [ "$status" = "enabled" ]; then
            nmcli radio wifi off
            notify-send -u normal -i network-wireless-offline \
                "WiFi Disabled" "WiFi radio has been turned off"
        else
            nmcli radio wifi on
            notify-send -u normal -i network-wireless \
                "WiFi Enabled" "WiFi radio has been turned on"
        fi
        ;;
    editor|*)
        nm-connection-editor &
        ;;
esac
