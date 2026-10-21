#!/usr/bin/env bash
# App launcher with "move-to-close": opens fuzzel and dismisses it the moment
# the mouse is moved. Navigate with the keyboard (type to filter, Enter to run);
# touching the mouse closes the launcher.

threshold=10   # px of cursor movement that counts as "moved"
poll=0.05      # seconds between cursor checks

# If a launcher is already up, a second press just closes it (toggle).
if pgrep -x fuzzel >/dev/null; then
    pkill -x fuzzel
    exit 0
fi

IFS=', ' read -r sx sy <<< "$(hyprctl cursorpos 2>/dev/null)"

fuzzel &
fpid=$!

# Watch the cursor while fuzzel is running.
while kill -0 "$fpid" 2>/dev/null; do
    IFS=', ' read -r cx cy <<< "$(hyprctl cursorpos 2>/dev/null)"
    if [[ "$cx" =~ ^-?[0-9]+$ && "$cy" =~ ^-?[0-9]+$ ]]; then
        dx=$(( cx - sx )); dy=$(( cy - sy ))
        (( dx < 0 )) && dx=$(( -dx ))
        (( dy < 0 )) && dy=$(( -dy ))
        if (( dx + dy > threshold )); then
            pkill -x fuzzel
            break
        fi
    fi
    sleep "$poll"
done
