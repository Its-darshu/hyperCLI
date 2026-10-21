# hyperCLI

A minimalist, macOS & iOS-inspired **Liquid Glass** desktop environment for Hyprland on Fedora Linux.

---

## Highlights

- **Liquid Glass Waybar**: Floating segmented frosted glass bar with real hardware blur, hover-to-reveal autohide, and system telemetry.
- **macOS Alt+Tab Switcher**: Centered horizontal window switcher with MRU ordering, application icons, window titles, workspace badges, and smooth keyboard navigation.
- **Audio Output Switcher**: Control Center style popup for 1-click switching between Bluetooth, speakers, headphones, and HDMI audio.
- **Minimalist Power Menu**: Clean typography-first `wlogout` interface for quick system actions.
- **Live Wallpaper Engine**: Smooth video wallpapers via `mpvpaper` with automatic battery optimization.

---

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/Its-darshu/hyperCLI.git ~/Project/hyperland
cd ~/Project/hyperland

# 2. Run the automated installer
bash setup-hyprland-fedora.sh

# 3. Log out and select Hyprland at the login screen
```

> For the comprehensive guide, configuration mapping, and complete cheat sheet, see **[INSTRUCTIONS.md](INSTRUCTIONS.md)**.

---

## Essential Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Alt + Tab` | Window Switcher (cycle forward; release Alt to focus) |
| `Alt + Shift + Tab` | Window Switcher (cycle backward) |
| `Super + Enter` | Open Terminal (`gnome-terminal`) |
| `Super + A` | Application Launcher (`fuzzel`) |
| `Super + Q` | Close Active Window |
| `Super + E` | File Manager (`thunar`) |
| `Super + B` | Web Browser (`brave-browser`) |
| `Super + Up / Down` | Maximize / Minimize Window |
| `Super + 1` .. `0` | Switch Workspace 1–10 |
| `Super + L` | Lock Screen (`hyprlock`) |
| `Super + P` | Power Menu (`wlogout`) |

---

## Repository Structure

| File / Folder | Purpose |
| :--- | :--- |
| [`hyprland.conf`](hyprland.conf) | Primary Hyprland configuration, monitors, animations, blur |
| [`keybinds.conf`](keybinds.conf) | Keybindings and modifier release triggers |
| [`window-switcher.py`](window-switcher.py) | Liquid Glass Alt+Tab switcher daemon |
| [`switcher.sh`](switcher.sh) | Switcher IPC CLI and launcher script |
| [`audio-switcher-popup.py`](audio-switcher-popup.py) | Audio device selector popup |
| [`waybar/`](waybar/) | Liquid Glass status bar layout and stylesheet |
| [`wlogout/`](wlogout/) | Fullscreen typography power menu layout and CSS |
| [`autostart.conf`](autostart.conf) | Startup daemons and background services |
| [`rules.conf`](rules.conf) | Window placement, floating, and layer blur rules |
| [`INSTRUCTIONS.md`](INSTRUCTIONS.md) | Detailed installation, configuration, and keybinding guide |

---

## License

Personal dotfiles — feel free to use, modify, and adapt for your own setup.
