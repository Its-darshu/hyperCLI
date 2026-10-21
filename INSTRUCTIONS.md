# hyperCLI — Setup & Instructions Guide

Comprehensive guide to installing, configuring, and using the Liquid Glass Hyprland desktop environment on Fedora Linux.

---

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [Configuration & Deploy Model](#configuration--deploy-model)
3. [Window Switcher (Liquid Glass macOS Alt+Tab)](#window-switcher-liquid-glass-macos-alttab)
4. [Complete Keyboard Shortcuts](#complete-keyboard-shortcuts)
   - [Applications & Launchers](#applications--launchers)
   - [Window Management & Navigation](#window-management--navigation)
   - [Workspaces & Scratchpad](#workspaces--scratchpad)
   - [Hardware Controls & Audio](#hardware-controls--audio)
   - [Wallpaper & Session](#wallpaper--session)
5. [Custom Features](#custom-features)
   - [Liquid Glass Waybar & Autohide](#liquid-glass-waybar--autohide)
   - [Interactive Audio Output Switcher](#interactive-audio-output-switcher)
   - [Live Wallpaper Shifter](#live-wallpaper-shifter)
   - [Smart Minimize & Restore](#smart-minimize--restore)
6. [Troubleshooting & FAQs](#troubleshooting--faqs)

---

## Installation & Setup

### Prerequisites
- **Operating System**: Fedora Linux 43+ (Workstation / Minimal)
- **Display Server**: Wayland / Hyprland 0.55+
- **Hardware**: Intel, AMD, or NVIDIA hybrid laptop/desktop

### 1. Run the Installer
```bash
git clone https://github.com/Its-darshu/hyperCLI.git ~/Project/hyperland
cd ~/Project/hyperland
bash setup-hyprland-fedora.sh
```

### 2. Log in to Hyprland
1. Log out of your current session.
2. At the GDM login screen, click the gear icon in the bottom right corner.
3. Select **Hyprland**.
4. Log in.

---

## Configuration & Deploy Model

This repository is the source code repository. Hyprland and Waybar read their active configuration from `~/.config/`.

### File Mapping

| Repository Path | Live Target Path | Description |
| :--- | :--- | :--- |
| `*.conf` | `~/.config/hypr/` | Core Hyprland configuration files |
| `*.sh`, `*.py` | `~/.config/hypr/scripts/` | Shell and Python helper scripts |
| `waybar/` | `~/.config/waybar/` | Status bar layout and Liquid Glass CSS |
| `wlogout/` | `~/.config/wlogout/` | Fullscreen typography power menu |
| `fish/` | `~/.config/fish/` | Fish shell functions and configuration |
| `fastfetch/` | `~/.config/fastfetch/` | Terminal banner configuration |
| `starship/` | `~/.config/starship.toml` | Minimal shell prompt |

### Applying Changes
After making edits in the repository, copy them to `~/.config/` and reload:

```bash
# Reload Hyprland configuration
hyprctl reload

# Verify syntax (should output empty)
hyprctl configerrors
```

---

## Window Switcher (Liquid Glass macOS Alt+Tab)

A custom, native Python GTK 3 Layer Shell switcher daemon with GPU-accelerated background blur, matching the Liquid Glass aesthetic.

### Controls
- **`Alt + Tab`**: Hold `Alt`, tap `Tab` once to immediately highlight the next most recently used application. Tap `Tab` repeatedly to cycle forward.
- **`Alt + Shift + Tab`**: Cycle backward through open windows.
- **`Release Alt`**: Immediately switches to the selected window and brings it to the active workspace.
- **`Escape`**: Cancels switching and restores original window focus.
- **`Left / Right Arrows`**: Step through cards horizontally.
- **`1` – `9`**: Jump directly to a card by its position index.
- **Mouse Click**: Click any card to focus that window immediately; click the darkened backdrop to cancel.

---

## Complete Keyboard Shortcuts

### Applications & Launchers
| Shortcut | Action | Command / Target |
| :--- | :--- | :--- |
| `Super + Enter` | Terminal | GNOME Terminal |
| `Super + Q` | Close Window | `killactive` |
| `Super + A` | Application Launcher | Fuzzel (`launcher.sh`) |
| `Super + E` | File Manager | Thunar |
| `Super + B` | Web Browser | Brave Browser |
| `Super + V` | Clipboard Picker | Cliphist Picker (`cliphist-picker.sh`) |

### Window Management & Navigation
| Shortcut | Action |
| :--- | :--- |
| `Super + F` | Toggle Fullscreen (mode 0) |
| `Super + Shift + F` | Toggle Floating Mode |
| `Super + Up` | Maximize window, or restore the last minimized window |
| `Super + Down` | Minimize active window to `special:minimized` |
| `Super + J` | Toggle Dwindle split direction (horizontal/vertical) |
| `Super + ;` | Toggle Dwindle pseudo-tiling |
| `Super + Left / Right` | Move focus to adjacent window |
| `Super + Ctrl + H / J / K / L` | Vim-style focus navigation (Left, Down, Up, Right) |
| `Super + Shift + Arrows` | Move active window position |
| `Super + Alt + Arrows` | Resize active window (30px increments) |
| `Super + LMB Drag` | Move floating window |
| `Super + RMB Drag` | Resize floating window |

### Workspaces & Scratchpad
| Shortcut | Action |
| :--- | :--- |
| `Super + 1` .. `0` | Switch to workspace 1 through 10 |
| `Super + Shift + 1` .. `0` | Move active window to workspace 1–10 (stay on current workspace) |
| `Super + Ctrl + Left / Right` | Move active window to adjacent workspace and follow it |
| `Super + Scroll Wheel` | Cycle workspaces from the status bar |
| `Super + ~` (`grave`) | Toggle scratchpad dropdown workspace |
| `Super + Shift + ~` | Move active window into the scratchpad |

### Hardware Controls & Audio
| Shortcut | Action |
| :--- | :--- |
| `XF86AudioRaiseVolume` | Volume Up (+5%) with on-screen HUD |
| `XF86AudioLowerVolume` | Volume Down (-5%) with on-screen HUD |
| `XF86AudioMute` | Toggle speaker mute |
| `XF86AudioMicMute` | Toggle microphone mute |
| `XF86MonBrightnessUp` | Display Brightness Up (+5%) with on-screen HUD |
| `XF86MonBrightnessDown` | Display Brightness Down (-5%) with on-screen HUD |
| `Super + N` | Toggle Night Light (warm color filter via `hyprsunset`) |
| `Super + Shift + B` | Toggle Waybar autohide / pin status |
| `XF86AudioPlay / Pause` | Media Play / Pause (`playerctl`) |
| `XF86AudioNext / Prev` | Next / Previous track (`playerctl`) |

### Wallpaper & Session
| Shortcut | Action |
| :--- | :--- |
| `Super + W` | Next live wallpaper (`wallpaper-shift.sh next`) |
| `Super + Shift + W` | Interactive live wallpaper picker |
| `Super + Alt + W` | Pause / resume live video wallpaper |
| `Print` | Capture fullscreen screenshot (saved + clipboard) |
| `Super + S` | Interactive region screenshot (saved + clipboard) |
| `Super + Shift + S` | Region screenshot directly to clipboard |
| `Super + L` | Lock screen (`hyprlock`) |
| `Super + P` | Power Menu submap (tap `1`=Lock, `2`=Logout, `3`=Sleep, `4`=Reboot, `5`=Shutdown, `Esc`=Cancel) |
| `Super + Shift + M` | Exit Hyprland session |

---

## Custom Features

### Liquid Glass Waybar & Autohide
- **Design**: Floating segmented frosted glass capsules (Workspaces & Title, Clock & Calendar, Hardware & Controls).
- **Autohide Daemon**: Managed by `waybar-autohide.sh`. Waybar remains tucked away at the bottom edge and reveals automatically on bottom-edge mouse hover.
- **Pinning**: Press `Super + Shift + B` to pin the bar permanently visible or unpin it back to autohide mode.

### Interactive Audio Output Switcher
- Clicking the audio module on Waybar triggers `audio-switcher-popup.py`.
- Features an iOS Control Center style frosted glass popup that automatically lists all connected Bluetooth devices, built-in speakers, 3.5mm headphones, and HDMI audio sinks.
- Switching devices automatically migrates all running audio streams and normalizes volume levels seamlessly.

### Live Wallpaper Shifter
- Managed by `wallpaper-shift.sh` using `mpvpaper`.
- Cycles 4K video wallpapers seamlessly with battery detection (automatically pauses live rendering when on battery power to preserve battery life).

### Smart Minimize & Restore
- `Super + Down` sends any window to `special:minimized`.
- `Super + Up` restores the most recently minimized window back to your active workspace, or maximizes the current window if nothing is minimized.
- The Alt+Tab switcher marks minimized windows with a `Min` badge and restores them directly when selected.

---

## Troubleshooting & FAQs

### Alt+Tab isn't responding
Verify that the background daemon is running:
```bash
~/.config/hypr/scripts/switcher.sh status
```
If not running, launch it manually or restart:
```bash
~/.config/hypr/scripts/switcher.sh init
```

### Checking for Configuration Errors
Run:
```bash
hyprctl configerrors
```
If errors are reported, check the file indicated and review recent edits.

### Restarting Waybar
```bash
pkill -x waybar
~/.config/hypr/scripts/waybar-autohide.sh &
```
