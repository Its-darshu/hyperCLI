#!/usr/bin/env bash
# switcher.sh — Liquid Glass macOS-inspired Alt+Tab Window Switcher
# IPC client and launcher for window-switcher.py

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 || echo /usr/bin/python3)"

# Find window-switcher.py: current dir, ~/.config/hypr/scripts, or ~/Project/hyperland
if [ -f "$DIR/window-switcher.py" ]; then
    SWITCHER_PY="$DIR/window-switcher.py"
elif [ -f "$HOME/.config/hypr/scripts/window-switcher.py" ]; then
    SWITCHER_PY="$HOME/.config/hypr/scripts/window-switcher.py"
elif [ -f "$HOME/Project/hyperland/window-switcher.py" ]; then
    SWITCHER_PY="$HOME/Project/hyperland/window-switcher.py"
else
    echo "ERROR: window-switcher.py not found" >&2
    exit 1
fi

ACTION="${1:-next}"

case "$ACTION" in
    init|daemon)
        # Kill previous hyprswitch daemon if still running
        pkill -x hyprswitch 2>/dev/null || true
        pkill -f "window-switcher.py daemon" 2>/dev/null || true
        sleep 0.2
        exec "$PYTHON_BIN" "$SWITCHER_PY" daemon
        ;;
    gui)
        # Backwards-compatibility for older hyprswitch keybindings
        if echo "$*" | grep -qE "reverse|shift"; then
            exec "$PYTHON_BIN" "$SWITCHER_PY" prev
        else
            exec "$PYTHON_BIN" "$SWITCHER_PY" next
        fi
        ;;
    next|prev|close|cancel|status|quit)
        exec "$PYTHON_BIN" "$SWITCHER_PY" "$ACTION"
        ;;
    *)
        exec "$PYTHON_BIN" "$SWITCHER_PY" next
        ;;
esac
