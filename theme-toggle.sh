#!/usr/bin/env bash
# System Dark / White (Light) Theme Switcher
# Toggles GNOME/GTK system theme, Fuzzel, Cursor, and updates Waybar button (keeps terminal dark)

STATE_FILE="$HOME/.config/hypr/theme-mode"
GTK3_DIR="$HOME/.config/gtk-3.0"
GTK4_DIR="$HOME/.config/gtk-4.0"
FUZZEL_DIR="$HOME/.config/fuzzel"

get_current_mode() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
        return
    fi

    local gset
    gset=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "'prefer-dark'")
    if [[ "$gset" == *"prefer-light"* ]]; then
        echo "light"
    else
        echo "dark"
    fi
}

set_theme() {
    local target="$1"

    if [ "$target" = "light" ]; then
        echo "light" > "$STATE_FILE"

        # 1. Update GNOME / FreeDesktop portal color-scheme & GTK theme
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' 2>/dev/null || true

        # 2. Update gtk-3.0 and gtk-4.0 settings.ini
        for ini in "$GTK3_DIR/settings.ini" "$GTK4_DIR/settings.ini"; do
            if [ -f "$ini" ]; then
                sed -i 's/gtk-theme-name=.*/gtk-theme-name=adw-gtk3/' "$ini"
                sed -i 's/gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=0/' "$ini"
            fi
        done

        # 3. Update GTK3 colors stylesheet
        if [ -f "$GTK3_DIR/gtk-light.css" ]; then
            cp "$GTK3_DIR/gtk-light.css" "$GTK3_DIR/gtk.css"
        fi

        # 4. GNOME Terminal remains dark (per user preference: terminal always stays dark)
        gsettings set org.gnome.Terminal.Legacy.Settings theme-variant 'dark' 2>/dev/null || true
        term_profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
        if [ -n "$term_profile" ]; then
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ use-theme-colors false 2>/dev/null || true
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ background-color '#161312' 2>/dev/null || true
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ foreground-color '#e9e1de' 2>/dev/null || true
        fi

        # 5. Update Fuzzel launcher theme
        if [ -f "$FUZZEL_DIR/fuzzel_theme-light.ini" ]; then
            cp "$FUZZEL_DIR/fuzzel_theme-light.ini" "$FUZZEL_DIR/fuzzel_theme.ini"
        fi

        # 6. Update Cursor / VS Code if present
        python3 -c '
import json, os
path = os.path.expanduser("~/.config/Cursor/User/settings.json")
if os.path.exists(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
        data["workbench.colorTheme"] = "Default Light Modern"
        data["window.autoDetectColorScheme"] = True
        with open(path, "w") as f:
            json.dump(data, f, indent=4)
    except Exception:
        pass
' 2>/dev/null || true

        # 7. Update Brave browser theme if present
        python3 -c '
import json, os
path = os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/Default/Preferences")
if os.path.exists(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
        data.setdefault("browser", {}).setdefault("theme", {})["color_scheme"] = 1
        with open(path, "w") as f:
            json.dump(data, f)
    except Exception:
        pass
' 2>/dev/null || true

        # 8. Notify user
        if command -v dunstify >/dev/null 2>&1; then
            dunstify -a "System Theme" -h string:x-dunst-stack-tag:theme -i weather-clear "System Theme: White / Light" "Switched system to Light mode" -t 1500
        else
            notify-send -u normal -i weather-clear "System Theme: White / Light" "Switched system to Light mode"
        fi

    else
        echo "dark" > "$STATE_FILE"

        # 1. Update GNOME / FreeDesktop portal color-scheme & GTK theme
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true

        # 2. Update gtk-3.0 and gtk-4.0 settings.ini
        for ini in "$GTK3_DIR/settings.ini" "$GTK4_DIR/settings.ini"; do
            if [ -f "$ini" ]; then
                sed -i 's/gtk-theme-name=.*/gtk-theme-name=adw-gtk3-dark/' "$ini"
                sed -i 's/gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=1/' "$ini"
            fi
        done

        # 3. Update GTK3 colors stylesheet
        if [ -f "$GTK3_DIR/gtk-dark.css" ]; then
            cp "$GTK3_DIR/gtk-dark.css" "$GTK3_DIR/gtk.css"
        fi

        # 4. Update GNOME Terminal theme & profile colors
        gsettings set org.gnome.Terminal.Legacy.Settings theme-variant 'dark' 2>/dev/null || true
        term_profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
        if [ -n "$term_profile" ]; then
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ use-theme-colors false 2>/dev/null || true
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ background-color '#161312' 2>/dev/null || true
            gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:/:${term_profile}/ foreground-color '#e9e1de' 2>/dev/null || true
        fi

        # 5. Update Fuzzel launcher theme
        if [ -f "$FUZZEL_DIR/fuzzel_theme-dark.ini" ]; then
            cp "$FUZZEL_DIR/fuzzel_theme-dark.ini" "$FUZZEL_DIR/fuzzel_theme.ini"
        fi

        # 6. Update Cursor / VS Code if present
        python3 -c '
import json, os
path = os.path.expanduser("~/.config/Cursor/User/settings.json")
if os.path.exists(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
        data["workbench.colorTheme"] = "Cursor Dark"
        data["window.autoDetectColorScheme"] = True
        with open(path, "w") as f:
            json.dump(data, f, indent=4)
    except Exception:
        pass
' 2>/dev/null || true

        # 7. Update Brave browser theme if present
        python3 -c '
import json, os
path = os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/Default/Preferences")
if os.path.exists(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
        data.setdefault("browser", {}).setdefault("theme", {})["color_scheme"] = 2
        with open(path, "w") as f:
            json.dump(data, f)
    except Exception:
        pass
' 2>/dev/null || true

        # 8. Notify user
        if command -v dunstify >/dev/null 2>&1; then
            dunstify -a "System Theme" -h string:x-dunst-stack-tag:theme -i weather-clear-night "System Theme: Dark" "Switched system to Dark mode" -t 1500
        else
            notify-send -u normal -i weather-clear-night "System Theme: Dark" "Switched system to Dark mode"
        fi
    fi

    # 9. Signal Waybar to refresh the custom/theme toggle button instantly (SIGRTMIN+9)
    pkill -RTMIN+9 waybar 2>/dev/null || true
}

case "${1:-status}" in
    status)
        current=$(get_current_mode)
        if [ "$current" = "light" ]; then
            printf '{"text":"󰖙","alt":"light","tooltip":"System Theme: White / Light Mode\\nClick to switch system to Dark Mode","class":"light"}\n'
        else
            printf '{"text":"󰖔","alt":"dark","tooltip":"System Theme: Dark Mode\\nClick to switch system to White / Light Mode","class":"dark"}\n'
        fi
        ;;
    toggle)
        current=$(get_current_mode)
        if [ "$current" = "light" ]; then
            set_theme "dark"
        else
            set_theme "light"
        fi
        ;;
    set)
        target="${2:-dark}"
        set_theme "$target"
        ;;
    *)
        echo "Usage: $0 {status|toggle|set [dark|light]}"
        exit 1
        ;;
esac
