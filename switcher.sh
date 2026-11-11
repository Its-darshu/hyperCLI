#!/usr/bin/env bash
# switcher.sh — Liquid Glass macOS-inspired Alt+Tab Window Switcher
# IPC client and launcher for window-switcher (Rust binary with Python fallback)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 || echo /usr/bin/python3)"

SWITCHER_BIN=""
SWITCHER_PY=""

# 1. Look for native compiled Rust binary
if [ -x "$DIR/window-switcher" ]; then
    SWITCHER_BIN="$DIR/window-switcher"
elif [ -x "$DIR/target/release/window-switcher" ]; then
    SWITCHER_BIN="$DIR/target/release/window-switcher"
elif [ -x "$HOME/.config/hypr/scripts/window-switcher" ]; then
    SWITCHER_BIN="$HOME/.config/hypr/scripts/window-switcher"
elif [ -x "$HOME/Project/hyperland/target/release/window-switcher" ]; then
    SWITCHER_BIN="$HOME/Project/hyperland/target/release/window-switcher"
elif [ -x "$HOME/Project/hyperland/window-switcher" ]; then
    SWITCHER_BIN="$HOME/Project/hyperland/window-switcher"
fi

# 2. Look for Python fallback script if binary not found
if [ -z "$SWITCHER_BIN" ]; then
    if [ -f "$DIR/window-switcher.py" ]; then
        SWITCHER_PY="$DIR/window-switcher.py"
    elif [ -f "$HOME/.config/hypr/scripts/window-switcher.py" ]; then
        SWITCHER_PY="$HOME/.config/hypr/scripts/window-switcher.py"
    elif [ -f "$HOME/Project/hyperland/window-switcher.py" ]; then
        SWITCHER_PY="$HOME/Project/hyperland/window-switcher.py"
    else
        echo "ERROR: Neither window-switcher binary nor window-switcher.py found" >&2
        exit 1
    fi
fi

run_cmd() {
    if [ -n "$SWITCHER_BIN" ]; then
        exec "$SWITCHER_BIN" "$@"
    else
        exec "$PYTHON_BIN" "$SWITCHER_PY" "$@"
    fi
}

ACTION="${1:-next}"

case "$ACTION" in
    init|daemon)
        # Kill previous daemon if running
        pkill -x hyprswitch 2>/dev/null || true
        pkill -f "window-switcher" 2>/dev/null || true
        sleep 0.2
        run_cmd daemon
        ;;
    gui)
        # Backwards-compatibility for older hyprswitch keybindings
        if echo "$*" | grep -qE "reverse|shift"; then
            run_cmd prev
        else
            run_cmd next
        fi
        ;;
    next|prev|close|cancel|status|quit)
        run_cmd "$ACTION"
        ;;
    *)
        run_cmd next
        ;;
esac
