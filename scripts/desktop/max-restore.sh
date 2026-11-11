#!/usr/bin/env bash
# Super+Up — "maximize / restore":
#   • If any window is minimized (in special:minimized), bring the most recent
#     one back to the current workspace and focus it. (Pairs with Super+Down.)
#   • Otherwise toggle maximize (fullscreen mode 1) on the focused window.

min=$(hyprctl clients -j | jq -r '[.[] | select(.workspace.name == "special:minimized")] | last | .address // empty')

if [ -n "$min" ]; then
    cur=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl dispatch movetoworkspace "${cur},address:${min}"
    hyprctl dispatch focuswindow "address:${min}"
else
    hyprctl dispatch fullscreen 1
fi
