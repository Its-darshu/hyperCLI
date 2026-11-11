#!/usr/bin/env bash
# Clipboard history picker: opens fuzzel in dmenu mode and closes it if the
# mouse moves (same move-to-close behaviour as launcher.sh).
#
# Usage: cliphist-picker.sh [copy|delete]
#   copy   (default) select an entry to copy it; a "Clear clipboard history"
#          entry is pinned to the top to wipe everything.
#   delete select an entry to remove just that entry from history.

# Enforce strict user-only file permissions (0600) to prevent clipboard snooping
umask 077

mode="${1:-copy}"
clear_entry="Clear clipboard history"

threshold=10
poll=0.10

if pgrep -x fuzzel >/dev/null; then
    pkill -x fuzzel
    exit 0
fi

IFS=', ' read -r sx sy <<< "$(hyprctl cursorpos 2>/dev/null)"

# Snapshot clipboard list into secure runtime temporary files (prefer XDG_RUNTIME_DIR in RAM)
tmp_dir="${XDG_RUNTIME_DIR:-/tmp}"
tmpin=$(mktemp -p "$tmp_dir" cliphist_in.XXXXXX)
tmpout=$(mktemp -p "$tmp_dir" cliphist_out.XXXXXX)

# Ensure temporary files containing clipboard data are ALWAYS sanitized and removed on exit or signal
cleanup() {
    [ -f "$tmpin" ] && rm -f "$tmpin" 2>/dev/null || true
    [ -f "$tmpout" ] && rm -f "$tmpout" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

if [[ "$mode" == "copy" ]]; then
    printf '%s\n' "$clear_entry" > "$tmpin"
fi
cliphist list >> "$tmpin"

fuzzel --dmenu < "$tmpin" > "$tmpout" &
fpid=$!
rm -f "$tmpin"

while kill -0 "$fpid" 2>/dev/null; do
    IFS=', ' read -r cx cy <<< "$(hyprctl cursorpos 2>/dev/null)"
    if [[ "$cx" =~ ^-?[0-9]+$ && "$cy" =~ ^-?[0-9]+$ ]]; then
        dx=$(( cx - sx )); dy=$(( cy - sy ))
        (( dx < 0 )) && dx=$(( -dx ))
        (( dy < 0 )) && dy=$(( -dy ))
        if (( dx + dy > threshold )); then
            kill "$fpid" 2>/dev/null
            exit 0
        fi
    fi
    sleep "$poll"
done

if [[ -s "$tmpout" ]]; then
    if [[ "$mode" == "copy" && "$(cat "$tmpout")" == "$clear_entry" ]]; then
        cliphist wipe
        notify-send "Clipboard" "History cleared" 2>/dev/null
    elif [[ "$mode" == "delete" ]]; then
        cliphist delete < "$tmpout"
        notify-send "Clipboard" "Entry deleted" 2>/dev/null
    else
        cliphist decode < "$tmpout" | wl-copy
    fi
fi
