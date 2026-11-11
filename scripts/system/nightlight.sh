#!/usr/bin/env bash
# Toggle Night Light (wlsunset) on or off.

if pgrep -x wlsunset >/dev/null; then
    pkill -x wlsunset
    dunstify -a "Night Light" -h string:x-dunst-stack-tag:nightlight -i display-brightness "Night Light: Off" -t 1500
else
    # Run wlsunset in background. Default temp 4000K.
    wlsunset -t 4000 -T 6500 >/dev/null 2>&1 &
    dunstify -a "Night Light" -h string:x-dunst-stack-tag:nightlight -i display-brightness "Night Light: On" -t 1500
fi
