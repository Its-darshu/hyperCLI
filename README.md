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
bash install/setup-hyprland-fedora.sh

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

```text
hyperCLI/
├── config/              # Hyprland core configuration files
│   ├── hyprland.conf    # Main configuration, display, animations, and blur
│   ├── keybinds.conf    # Keybindings and modifier release triggers
│   ├── autostart.conf   # Startup daemons and background services
│   ├── rules.conf       # Window placement, floating, and layer blur rules
│   ├── hypridle.conf    # Idle management and screen dimming
│   └── hyprlock.conf    # Lock screen layout and authentication
├── scripts/             # Modular shell helper scripts
│   ├── system/          # Brightness, volume, night light, theme toggler
│   ├── network/         # WiFi and Bluetooth menu and toggles
│   ├── desktop/         # Wallpaper shifter, app launcher, window switcher, maximize/restore
│   ├── waybar/          # Waybar autohide daemon, pin toggle, position toggle, audio switcher
│   └── utilities/       # Clipboard picker and system utilities
├── src/                 # Native compiled Rust application source
│   └── bin/
│       ├── window_switcher.rs       # macOS Liquid Glass Alt+Tab switcher daemon
│       └── audio_switcher_popup.rs  # Audio output selector popup
├── waybar/              # Liquid Glass status bar layout and stylesheet
├── wlogout/             # Fullscreen typography power menu layout and CSS
├── install/             # System and tool installation scripts
│   ├── setup-hyprland-fedora.sh     # Fedora base system package installer
│   └── setup-window-tools.sh        # Rust switcher and popup build/deploy script
├── tests/               # Repository verification and test suites
│   └── verify-repo.sh   # Syntax, path reference, and build checks
├── Cargo.toml           # Cargo manifest for native Rust binaries
├── README.md
└── INSTRUCTIONS.md
```

---

## License

Personal dotfiles — feel free to use, modify, and adapt for your own setup.
