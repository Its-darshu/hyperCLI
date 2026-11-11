#!/usr/bin/env bash
# switcher.sh — Liquid Glass macOS-inspired Alt+Tab Window Switcher
# Native Rust IPC client and launcher for window-switcher

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHER_BIN=""

# Look for native compiled Rust binary
cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
if [ -x "$DIR/window-switcher" ]; then
    SWITCHER_BIN="$DIR/window-switcher"
elif [ -x "$DIR/../../target/release/window-switcher" ]; then
    SWITCHER_BIN="$DIR/../../target/release/window-switcher"
elif [ -x "$DIR/target/release/window-switcher" ]; then
    SWITCHER_BIN="$DIR/target/release/window-switcher"
elif [ -x "$cfg_dir/desktop/window-switcher" ]; then
    SWITCHER_BIN="$cfg_dir/desktop/window-switcher"
elif [ -x "$cfg_dir/window-switcher" ]; then
    SWITCHER_BIN="$cfg_dir/window-switcher"
fi

if [ -z "$SWITCHER_BIN" ]; then
    echo "ERROR: window-switcher binary not found. Build it with: cargo build --release" >&2
    exit 1
fi

ACTION="${1:-next}"

case "$ACTION" in
    init|daemon)
        pkill -x hyprswitch 2>/dev/null || true
        pkill -f "window-switcher" 2>/dev/null || true
        sleep 0.2
        exec "$SWITCHER_BIN" daemon
        ;;
    gui)
        if echo "$*" | grep -qE "reverse|shift"; then
            exec "$SWITCHER_BIN" prev
        else
            exec "$SWITCHER_BIN" next
        fi
        ;;
    next|prev|close|cancel|status|quit)
        exec "$SWITCHER_BIN" "$ACTION"
        ;;
    *)
        exec "$SWITCHER_BIN" next
        ;;
esac
