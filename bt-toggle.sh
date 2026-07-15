#!/usr/bin/env bash
# bt-toggle.sh — Bluetooth helper for Waybar
# Usage:
#   bt-toggle.sh          → open blueman-manager (left-click)
#   bt-toggle.sh manager  → open blueman-manager (same as no arg)
#   bt-toggle.sh scan     → start BT discovery + open blueman-manager (right-click)
#   bt-toggle.sh toggle   → toggle BT power on/off (middle-click)

set -euo pipefail

notify() {
    notify-send -i bluetooth -t 3000 "Bluetooth" "$1"
}

# Returns 0 if bluetooth is powered on
bt_powered() {
    bluetoothctl show | grep -q "Powered: yes"
}

# Returns 0 if discovery is already active
bt_discovering() {
    bluetoothctl show | grep -q "Discovering: yes"
}

case "${1:-manager}" in

    scan)
        if ! bt_powered; then
            notify "Bluetooth is off. Turn it on first (middle-click)."
            exit 1
        fi

        if bt_discovering; then
            notify "Discovery already running."
        else
            # Run scan in background: 30 s then stop
            (
                bluetoothctl scan on &
                SCAN_PID=$!
                sleep 30
                kill "$SCAN_PID" 2>/dev/null
                bluetoothctl scan off 2>/dev/null
            ) &
            notify "Scanning for devices (30 s)…"
        fi

        # Open blueman-manager (or focus it if already open)
        pgrep -x blueman-manager >/dev/null || blueman-manager &
        ;;

    toggle)
        if bt_powered; then
            bluetoothctl power off
            notify "Bluetooth OFF"
        else
            bluetoothctl power on
            notify "Bluetooth ON"
        fi
        ;;

    manager|"")
        pgrep -x blueman-manager >/dev/null || blueman-manager &
        ;;

    *)
        echo "Usage: $(basename "$0") [scan|toggle|manager]" >&2
        exit 1
        ;;
esac
