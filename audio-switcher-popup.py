#!/usr/bin/env python3
"""
audio-switcher-popup.py
Modern smartphone-style Audio Output Switcher popup for Hyprland & Waybar.
Uses GTK 3 with GtkLayerShell.
"""

import sys
import os
import subprocess
import json
import time
import atexit
import signal

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GtkLayerShell, GLib

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PINNED_FILE = os.path.join(RUNTIME_DIR, "waybar-pinned")
AUTOHIDE_PID_FILE = os.path.join(RUNTIME_DIR, "waybar-autohide.pid")

def pin_waybar():
    try:
        with open(PINNED_FILE, "w") as f:
            f.write("1\n")
        if os.path.exists(AUTOHIDE_PID_FILE):
            with open(AUTOHIDE_PID_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, signal.SIGUSR2)
    except Exception:
        pass

def unpin_waybar():
    try:
        if os.path.exists(PINNED_FILE):
            os.remove(PINNED_FILE)
        if os.path.exists(AUTOHIDE_PID_FILE):
            with open(AUTOHIDE_PID_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, signal.SIGUSR2)
    except Exception:
        pass

atexit.register(unpin_waybar)
for sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, lambda s, f: sys.exit(0))

pin_waybar()

CSS = """
* {
    all: unset;
    font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", -apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, sans-serif;
}

window {
    background-color: transparent;
}

#backdrop {
    background-color: transparent;
}

#card {
    background-color: rgba(18, 18, 24, 0.65);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 20px;
    padding: 14px 16px;
    box-shadow: 0 12px 36px rgba(0, 0, 0, 0.45),
                inset 0 1px 0 rgba(255, 255, 255, 0.18);
}

#header-title {
    color: #f8fafc;
    font-size: 13.5px;
    font-weight: 700;
}

#header-subtitle {
    color: rgba(255, 255, 255, 0.50);
    font-size: 10.5px;
    margin-bottom: 10px;
}

.device-row {
    background-color: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 14px;
    padding: 9px 12px;
    margin: 3px 0;
    transition: all 150ms ease;
}

.device-row:hover {
    background-color: rgba(255, 255, 255, 0.12);
    border-color: rgba(255, 255, 255, 0.20);
}

.device-row.active {
    background-color: rgba(56, 189, 248, 0.18);
    border: 1px solid rgba(56, 189, 248, 0.40);
    box-shadow: 0 2px 10px rgba(56, 189, 248, 0.15),
                inset 0 1px 0 rgba(255, 255, 255, 0.15);
}

.device-icon {
    font-size: 18px;
    color: #38bdf8;
    margin-right: 12px;
}

.device-icon.inactive {
    color: rgba(255, 255, 255, 0.60);
}

.device-name {
    color: #f1f5f9;
    font-size: 12.5px;
    font-weight: 600;
}

.device-name.active {
    color: #ffffff;
    font-weight: 700;
}

.device-desc {
    color: rgba(255, 255, 255, 0.50);
    font-size: 10px;
}

.device-desc.active {
    color: #bae6fd;
}

.check-icon {
    font-size: 15px;
    color: #38bdf8;
    font-weight: 700;
}
"""

def detect_audio_targets():
    try:
        def_sink = subprocess.check_output(["pactl", "get-default-sink"], text=True).strip()
    except Exception:
        def_sink = ""

    try:
        sinks = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sinks"], text=True))
    except Exception:
        sinks = []

    try:
        cards = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "cards"], text=True))
    except Exception:
        cards = []

    targets = []
    seen_keys = set()

    # 1. Connected Bluetooth sinks
    for s in sinks:
        name = s.get("name", "")
        props = s.get("properties", {})
        bus = props.get("device.bus", "")
        desc = s.get("description", "")
        if bus == "bluetooth" or "bluez" in name.lower():
            key = f"sink:{name}"
            seen_keys.add(key)
            targets.append({
                "key": key,
                "name": desc,
                "subtitle": "Bluetooth Audio",
                "icon": "󰥰",
                "is_active": (name == def_sink),
                "action": {"type": "sink", "sink": name, "id": props.get("object.id")}
            })

    # 2. Built-in Card Profiles (Speakers and Wired Headphones)
    for c in cards:
        cname = c.get("name", "")
        active_prof = c.get("active_profile", "")
        profiles = c.get("profiles", {})
        
        speaker_prof = None
        headphones_prof = None
        for pname in profiles:
            if "Speaker" in pname and not speaker_prof:
                speaker_prof = pname
            elif "Headphone" in pname and not headphones_prof:
                headphones_prof = pname

        if speaker_prof:
            is_active = ("Speaker" in def_sink or ("Speaker" in active_prof and "bluez" not in def_sink and "HDMI" not in def_sink))
            targets.append({
                "key": f"card:{cname}:speaker",
                "name": "Internal Speakers",
                "subtitle": "Built-in Audio",
                "icon": "󰓃",
                "is_active": is_active,
                "action": {"type": "profile", "card": cname, "profile": speaker_prof, "sink_pattern": "Speaker"}
            })

        if headphones_prof:
            is_active = ("Headphone" in def_sink or ("Headphone" in active_prof and "bluez" not in def_sink and "HDMI" not in def_sink))
            targets.append({
                "key": f"card:{cname}:headphones",
                "name": "Wired Headphones",
                "subtitle": "3.5mm Audio Jack",
                "icon": "󰋋",
                "is_active": is_active,
                "action": {"type": "profile", "card": cname, "profile": headphones_prof, "sink_pattern": "Headphone"}
            })

    # 3. Connected external displays / HDMI
    for s in sinks:
        name = s.get("name", "")
        props = s.get("properties", {})
        desc = s.get("description", "")
        ports = s.get("ports", [])
        avail_ports = [p for p in ports if p.get("availability") == "available"]
        if avail_ports and ("hdmi" in desc.lower() or "displayport" in desc.lower()):
            key = f"sink:{name}"
            if key not in seen_keys:
                targets.append({
                    "key": key,
                    "name": "External Display",
                    "subtitle": "HDMI / DisplayPort",
                    "icon": "󰍹",
                    "is_active": (name == def_sink),
                    "action": {"type": "sink", "sink": name, "id": props.get("object.id")}
                })

    # 4. Any other non-bluetooth, non-internal sinks (e.g. USB DACs)
    for s in sinks:
        name = s.get("name", "")
        if name in [t.get("action", {}).get("sink") for t in targets] or "bluez" in name:
            continue
        props = s.get("properties", {})
        bus = props.get("device.bus", "")
        desc = s.get("description", "")
        if bus == "usb":
            key = f"sink:{name}"
            if key not in seen_keys:
                targets.append({
                    "key": key,
                    "name": desc,
                    "subtitle": "USB Audio Device",
                    "icon": "󰓃",
                    "is_active": (name == def_sink),
                    "action": {"type": "sink", "sink": name, "id": props.get("object.id")}
                })

    return targets

def get_current_volume():
    """Returns (volume_float, is_muted_bool) of the current default sink."""
    try:
        out = subprocess.check_output(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            stderr=subprocess.DEVNULL,
            text=True
        ).strip()
        parts = out.split()
        if len(parts) >= 2:
            vol = float(parts[1])
            muted = "[MUTED]" in out
            return vol, muted
    except Exception:
        pass
    try:
        def_sink = subprocess.check_output(
            ["pactl", "get-default-sink"],
            stderr=subprocess.DEVNULL,
            text=True
        ).strip()
        sinks = json.loads(subprocess.check_output(
            ["pactl", "-f", "json", "list", "sinks"],
            stderr=subprocess.DEVNULL,
            text=True
        ))
        for s in sinks:
            if s.get("name") == def_sink:
                vol_map = s.get("volume", {})
                vols = [v.get("value_percent", "100%").rstrip("%") for v in vol_map.values() if isinstance(v, dict)]
                if vols:
                    vol = float(vols[0]) / 100.0
                    muted = s.get("mute", False)
                    return vol, muted
    except Exception:
        pass
    return 1.0, False

def move_all_streams(target_sink):
    """Moves all active sink-inputs immediately to target_sink."""
    try:
        inputs_json = subprocess.check_output(
            ["pactl", "-f", "json", "list", "sink-inputs"],
            stderr=subprocess.DEVNULL,
            text=True
        )
        inputs = json.loads(inputs_json)
        for inp in inputs:
            idx = inp.get("index")
            if idx is not None:
                subprocess.run(["pactl", "move-sink-input", str(idx), target_sink], check=False)
    except Exception:
        pass

def switch_audio(action):
    try:
        cur_vol, cur_muted = get_current_volume()
        target_sink = None
        target_id = None

        if action["type"] == "profile":
            # Switch the card profile
            subprocess.run(["pactl", "set-card-profile", action["card"], action["profile"]], check=True)
            # Actively poll until the new sink node appears in PipeWire (up to 2.0s)
            start_time = time.time()
            pattern = action["sink_pattern"].lower()
            while time.time() - start_time < 2.0:
                try:
                    sinks = json.loads(subprocess.check_output(
                        ["pactl", "-f", "json", "list", "sinks"],
                        stderr=subprocess.DEVNULL,
                        text=True
                    ))
                    for s in sinks:
                        s_name = s.get("name", "").lower()
                        s_desc = s.get("description", "").lower()
                        if pattern in s_name or pattern in s_desc:
                            target_sink = s.get("name")
                            target_id = s.get("properties", {}).get("object.id")
                            break
                    if target_sink:
                        break
                except Exception:
                    pass
                time.sleep(0.02)
        elif action["type"] == "sink":
            target_sink = action["sink"]
            target_id = action.get("id")

        if target_sink:
            # Set default sink across both PulseAudio and WirePlumber layers
            subprocess.run(["pactl", "set-default-sink", target_sink], check=True)
            if target_id:
                subprocess.run(["wpctl", "set-default", str(target_id)], check=False)

            # Move active streams to the new sink
            move_all_streams(target_sink)

            # Preserve listening volume without resetting to quiet route defaults or exceeding unity
            if cur_vol is not None and cur_vol > 0.0:
                safe_vol = min(cur_vol, 1.0)
                if target_id:
                    subprocess.run(["wpctl", "set-volume", str(target_id), f"{safe_vol:.2f}"], check=False)
                    subprocess.run(["wpctl", "set-mute", str(target_id), "1" if cur_muted else "0"], check=False)
                else:
                    subprocess.run(["pactl", "set-sink-volume", target_sink, f"{int(safe_vol*100)}%"], check=False)
                    subprocess.run(["pactl", "set-sink-mute", target_sink, "1" if cur_muted else "0"], check=False)

        # Trigger instant Waybar refresh (SIGRTMIN+8)
        subprocess.run(["pkill", "-RTMIN+8", "waybar"], check=False)
    except Exception as e:
        print("Error switching audio:", e, file=sys.stderr)

def main():
    pin_waybar()
    win = Gtk.Window()
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.TOP)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.ON_DEMAND)
    GtkLayerShell.set_namespace(win, "audio-switcher")

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS.encode())
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    # Fullscreen backdrop event box for click-outside dismissal
    backdrop = Gtk.EventBox()
    backdrop.set_name("backdrop")
    backdrop.connect("button-press-event", lambda w, e: Gtk.main_quit())

    outer_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    outer_box.set_halign(Gtk.Align.END)
    outer_box.set_valign(Gtk.Align.END)
    outer_box.set_margin_bottom(48)
    outer_box.set_margin_end(60)

    # Card container
    card_event = Gtk.EventBox()
    card_event.connect("button-press-event", lambda w, e: True) # prevent dismiss on clicking card background

    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    card.set_name("card")
    card.set_size_request(280, -1)

    # Header
    hdr = Gtk.Label(label="󰓃  Media Output", xalign=0)
    hdr.set_name("header-title")
    card.add(hdr)

    sub = Gtk.Label(label="Select playback device", xalign=0)
    sub.set_name("header-subtitle")
    card.add(sub)

    targets = detect_audio_targets()

    for dev in targets:
        btn = Gtk.Button()
        btn.get_style_context().add_class("device-row")
        if dev["is_active"]:
            btn.get_style_context().add_class("active")

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        icon_lbl = Gtk.Label(label=dev["icon"])
        icon_lbl.get_style_context().add_class("device-icon")
        if not dev["is_active"]:
            icon_lbl.get_style_context().add_class("inactive")
        hbox.pack_start(icon_lbl, False, False, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        name_lbl = Gtk.Label(label=dev["name"], xalign=0)
        name_lbl.get_style_context().add_class("device-name")
        if dev["is_active"]:
            name_lbl.get_style_context().add_class("active")
        vbox.pack_start(name_lbl, False, False, 0)

        desc_lbl = Gtk.Label(label=dev["subtitle"], xalign=0)
        desc_lbl.get_style_context().add_class("device-desc")
        if dev["is_active"]:
            desc_lbl.get_style_context().add_class("active")
        vbox.pack_start(desc_lbl, False, False, 0)

        hbox.pack_start(vbox, True, True, 0)

        if dev["is_active"]:
            chk = Gtk.Label(label="󰄬")
            chk.get_style_context().add_class("check-icon")
            hbox.pack_end(chk, False, False, 0)

        btn.add(hbox)

        def make_handler(action, dev_name):
            def on_clicked(button):
                switch_audio(action)
                subprocess.run(["notify-send", "-u", "low", "-i", "audio-volume-high", "Audio Output", f"Switched to {dev_name}"], check=False)
                Gtk.main_quit()
            return on_clicked

        btn.connect("clicked", make_handler(dev["action"], dev["name"]))
        card.add(btn)

    card_event.add(card)
    outer_box.add(card_event)
    backdrop.add(outer_box)
    win.add(backdrop)

    win.connect("key-press-event", lambda w, e: Gtk.main_quit() if e.keyval == Gdk.KEY_Escape else None)

    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
