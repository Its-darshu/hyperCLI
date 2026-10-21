#!/usr/bin/env python3
"""
window-switcher.py
Liquid Glass macOS-inspired Alt+Tab Window Switcher for Hyprland.
Features:
- Centered horizontal window-switcher overlay
- Dark translucent glass background with subtle blur (via Hyprland layer-shell rules)
- Rounded rectangular window cards with large app icons, window title, and workspace badge
- Active card outline with sky blue accent glow
- Precise MRU ordering with zero double-press bug
- Instant response via local UNIX socket daemon
- Full keyboard (Alt hold/release, Tab, Shift+Tab, Arrows, Esc, Numbers) & Mouse support
"""

import sys
import os
import subprocess
import json
import glob
import time
import socket
import select
import signal
import atexit

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GdkPixbuf, GtkLayerShell, GLib, Pango

SOCKET_PATH = f"/run/user/{os.getuid()}/hypr-window-switcher.sock"

CSS = """
* {
    all: unset;
    font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", -apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, sans-serif;
}

window {
    background-color: transparent;
}

#backdrop {
    background-color: rgba(4, 6, 10, 0.40);
}

#switcher-container {
    background-color: rgba(18, 18, 24, 0.74);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 24px;
    padding: 16px 22px;
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.65),
                inset 0 1px 0 rgba(255, 255, 255, 0.22);
}

#summary-bar {
    margin-bottom: 14px;
    padding: 0 4px;
}

#summary-title {
    color: #ffffff;
    font-size: 13px;
    font-weight: 700;
}

#summary-hint {
    color: rgba(255, 255, 255, 0.50);
    font-size: 10.5px;
    font-weight: 500;
    margin-left: 24px;
}

.window-card {
    background-color: rgba(255, 255, 255, 0.05);
    border: 1.5px solid rgba(255, 255, 255, 0.08);
    border-radius: 18px;
    padding: 14px 16px;
    margin: 4px;
    min-width: 175px;
    transition: all 160ms cubic-bezier(0.16, 1, 0.3, 1);
}

.window-card:hover {
    background-color: rgba(255, 255, 255, 0.10);
    border-color: rgba(255, 255, 255, 0.20);
}

.window-card.active {
    background-color: rgba(255, 255, 255, 0.15);
    border: 2px solid rgba(56, 189, 248, 0.90);
    border-radius: 18px;
    box-shadow: 0 0 24px rgba(56, 189, 248, 0.42),
                inset 0 1px 0 rgba(255, 255, 255, 0.32);
}

.card-title {
    color: rgba(255, 255, 255, 0.70);
    font-size: 11px;
    font-weight: 500;
}

.window-card.active .card-title {
    color: #ffffff;
    font-weight: 700;
}

.ws-badge {
    background-color: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 8px;
    color: rgba(255, 255, 255, 0.65);
    font-size: 9.5px;
    font-weight: 700;
    padding: 2px 7px;
    margin-left: 8px;
}

.window-card.active .ws-badge {
    background-color: rgba(56, 189, 248, 0.25);
    border-color: rgba(56, 189, 248, 0.60);
    color: #bae6fd;
}

.app-name {
    color: #f1f5f9;
    font-size: 12.5px;
    font-weight: 600;
    margin-top: 10px;
}

.window-card.active .app-name {
    color: #ffffff;
    font-weight: 700;
}
"""

def build_desktop_map():
    mapping = {}
    for d in ['/usr/share/applications', os.path.expanduser('~/.local/share/applications')]:
        if not os.path.exists(d):
            continue
        for p in glob.glob(os.path.join(d, '*.desktop')):
            try:
                wm_class, icon, name = None, None, None
                with open(p, 'r', errors='ignore') as f:
                    for line in f:
                        if line.startswith('StartupWMClass='):
                            wm_class = line.strip().split('=', 1)[1]
                        elif line.startswith('Icon=') and not icon:
                            icon = line.strip().split('=', 1)[1]
                        elif line.startswith('Name=') and not name:
                            name = line.strip().split('=', 1)[1]
                base = os.path.splitext(os.path.basename(p))[0]
                if icon:
                    mapping[base.lower()] = (icon, name)
                    if wm_class:
                        mapping[wm_class.lower()] = (icon, name)
            except Exception:
                pass
    return mapping

DESKTOP_MAP = build_desktop_map()
ICON_THEME = Gtk.IconTheme.get_default()

def resolve_icon(wm_class, title, size=72):
    candidates = []
    if wm_class:
        cl = wm_class.lower()
        candidates.append(wm_class)
        candidates.append(cl)
        if cl in DESKTOP_MAP:
            candidates.append(DESKTOP_MAP[cl][0])
        # Strip domain prefixes like org.gnome.Terminal -> Terminal
        parts = wm_class.split('.')
        if len(parts) > 1:
            candidates.append(parts[-1].lower())
            candidates.append(parts[-1])

    candidates.extend(['application-x-executable', 'window-new'])
    for c in candidates:
        if ICON_THEME.has_icon(c):
            try:
                return ICON_THEME.load_icon(c, size, Gtk.IconLookupFlags.FORCE_SIZE)
            except Exception:
                pass
    return None

def resolve_app_name(wm_class):
    if wm_class:
        cl = wm_class.lower()
        if cl in DESKTOP_MAP and DESKTOP_MAP[cl][1]:
            return DESKTOP_MAP[cl][1]
        parts = wm_class.split('.')
        return parts[-1].capitalize()
    return "Application"


class WindowSwitcherDaemon:
    def __init__(self):
        self.state = "IDLE"  # IDLE, SWITCHING, COMMITTING
        self.windows = []
        self.cards = []
        self.selected_idx = 0
        self.original_focused_addr = None
        self.last_advance_time = 0.0

        # UI Initialization
        self.win = Gtk.Window()
        GtkLayerShell.init_for_window(self.win)
        GtkLayerShell.set_layer(self.win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_keyboard_mode(self.win, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        GtkLayerShell.set_namespace(self.win, "window-switcher")

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.backdrop = Gtk.EventBox()
        self.backdrop.set_name("backdrop")
        self.backdrop.connect("button-press-event", self._on_backdrop_clicked)

        self.center_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.center_box.set_halign(Gtk.Align.CENTER)
        self.center_box.set_valign(Gtk.Align.CENTER)

        self.container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.container.set_name("switcher-container")
        self.container.connect("button-press-event", lambda w, e: True)

        # Summary Row (Title + Navigation Hints)
        self.summary_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.summary_box.set_name("summary-bar")

        self.summary_title = Gtk.Label(label="")
        self.summary_title.set_name("summary-title")
        self.summary_title.set_halign(Gtk.Align.START)
        self.summary_title.set_ellipsize(Pango.EllipsizeMode.END)
        self.summary_title.set_max_width_chars(52)
        self.summary_box.pack_start(self.summary_title, True, True, 0)

        self.summary_hint = Gtk.Label(label="Tab 󰌑 Next  ·  ⇧Tab Prev  ·  Release 󰘵 Select  ·  Esc Cancel")
        self.summary_hint.set_name("summary-hint")
        self.summary_hint.set_halign(Gtk.Align.END)
        self.summary_box.pack_end(self.summary_hint, False, False, 0)

        self.container.pack_start(self.summary_box, False, False, 0)

        # Scrolled container for horizontal window cards
        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        self.scrolled.set_shadow_type(Gtk.ShadowType.NONE)

        self.cards_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.cards_box.set_halign(Gtk.Align.CENTER)
        self.scrolled.add(self.cards_box)

        self.container.pack_start(self.scrolled, True, True, 0)
        self.center_box.pack_start(self.container, False, False, 0)
        self.backdrop.add(self.center_box)
        self.win.add(self.backdrop)

        self.win.connect("key-press-event", self._on_key_press)
        self.win.connect("key-release-event", self._on_key_release)

        # Setup UNIX socket server
        self._setup_socket_server()

    def _setup_socket_server(self):
        if os.path.exists(SOCKET_PATH):
            try:
                os.unlink(SOCKET_PATH)
            except OSError:
                pass
        self.server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_sock.bind(SOCKET_PATH)
        self.server_sock.listen(16)
        self.server_sock.setblocking(False)

        GLib.io_add_watch(self.server_sock.fileno(), GLib.IO_IN, self._on_socket_connect)

    def _on_socket_connect(self, fd, cond):
        try:
            client_sock, _ = self.server_sock.accept()
            client_sock.setblocking(False)
            GLib.io_add_watch(client_sock.fileno(), GLib.IO_IN, self._on_socket_data, client_sock)
        except Exception as e:
            print("Socket accept error:", e, file=sys.stderr)
        return True

    def _on_socket_data(self, fd, cond, client_sock):
        try:
            data = client_sock.recv(1024)
            if data:
                cmd = data.decode('utf-8').strip()
                self._handle_command(cmd, client_sock)
        except Exception as e:
            print("Socket recv error:", e, file=sys.stderr)
        finally:
            try:
                client_sock.close()
            except Exception:
                pass
        # Always return False so GLib removes this one-shot client watch
        return False

    def _handle_command(self, cmd_line, client_sock=None):
        parts = cmd_line.split()
        if not parts:
            return
        cmd = parts[0].upper()

        if cmd == "NEXT":
            self.advance(1)
            if client_sock:
                try: client_sock.sendall(b"OK\n"); client_sock.close()
                except Exception: pass
        elif cmd == "PREV":
            self.advance(-1)
            if client_sock:
                try: client_sock.sendall(b"OK\n"); client_sock.close()
                except Exception: pass
        elif cmd == "CLOSE":
            self.commit()
            if client_sock:
                try: client_sock.sendall(b"OK\n"); client_sock.close()
                except Exception: pass
        elif cmd == "CANCEL":
            self.cancel()
            if client_sock:
                try: client_sock.sendall(b"OK\n"); client_sock.close()
                except Exception: pass
        elif cmd == "STATUS":
            resp = json.dumps({"state": self.state, "windows": len(self.windows), "selected": self.selected_idx})
            if client_sock:
                try: client_sock.sendall(resp.encode() + b"\n"); client_sock.close()
                except Exception: pass
        elif cmd == "QUIT":
            if client_sock:
                try: client_sock.sendall(b"BYE\n"); client_sock.close()
                except Exception: pass
            Gtk.main_quit()

    def _query_eligible_windows(self):
        try:
            clients_raw = subprocess.check_output(['hyprctl', '-j', 'clients'], text=True)
            clients = json.loads(clients_raw)
        except Exception:
            clients = []

        try:
            active_raw = subprocess.check_output(['hyprctl', '-j', 'activewindow'], text=True)
            active = json.loads(active_raw)
            active_addr = active.get('address')
        except Exception:
            active_addr = None

        eligible = []
        for c in clients:
            if not c.get('mapped', True):
                continue
            title = c.get('title', '').strip()
            wm_class = c.get('class', '').strip()
            if not title and not wm_class:
                continue
            if wm_class in ['hypr-window-switcher', 'audio-switcher']:
                continue
            if c.get('swallowing') and c.get('swallowing') != "0x0":
                continue
            eligible.append(c)

        # Sort in MRU order by focusHistoryID (0 = current, 1 = previous, etc.)
        def sort_key(c):
            fhid = c.get('focusHistoryID', -1)
            if fhid >= 0:
                return (0, fhid)
            return (1, c.get('workspace', {}).get('id', 0), c.get('pid', 0))

        eligible.sort(key=sort_key)

        # Ensure active window is at index 0 if present
        if active_addr:
            for i, c in enumerate(eligible):
                if c.get('address') == active_addr:
                    if i != 0:
                        act = eligible.pop(i)
                        eligible.insert(0, act)
                    break

        return eligible, active_addr

    def advance(self, step=1):
        now = time.time()
        # Debounce rapid repeat triggers
        if self.state == "SWITCHING" and (now - self.last_advance_time) < 0.065:
            return
        self.last_advance_time = now

        if self.state == "IDLE":
            # Initial invocation
            self.windows, self.original_focused_addr = self._query_eligible_windows()
            if not self.windows:
                return

            if len(self.windows) == 1:
                self.selected_idx = 0
            else:
                # Core fix: Single Alt+Tab press immediately selects index 1 (the next window)
                if step >= 0:
                    self.selected_idx = 1
                else:
                    self.selected_idx = len(self.windows) - 1

            self._build_ui()
            self.state = "SWITCHING"
            self.win.show_all()
        else:
            # Subsequent invocation while open
            if not self.windows:
                return
            self.selected_idx = (self.selected_idx + step) % len(self.windows)
            self._update_highlight()

    def _build_ui(self):
        # Clear previous cards
        for ch in self.cards_box.get_children():
            self.cards_box.remove(ch)
        self.cards = []

        for i, w in enumerate(self.windows):
            card = Gtk.EventBox()
            card.set_visible_window(False)
            card.connect("button-press-event", self._on_card_clicked, i)
            card.connect("enter-notify-event", self._on_card_hover, i)

            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            inner.get_style_context().add_class("window-card")
            if i == self.selected_idx:
                inner.get_style_context().add_class("active")

            # Top row: Title above icon + WS badge
            top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
            card_title = Gtk.Label(label=w.get('title', 'Window'))
            card_title.get_style_context().add_class("card-title")
            card_title.set_halign(Gtk.Align.START)
            card_title.set_ellipsize(Pango.EllipsizeMode.END)
            card_title.set_max_width_chars(15)
            top_row.pack_start(card_title, True, True, 0)

            ws_name = str(w.get('workspace', {}).get('name', '1'))
            if ws_name.startswith('special:minimized'):
                ws_display = "Min"
            elif ws_name.startswith('special:'):
                ws_display = ws_name.replace('special:', '')[:4].capitalize()
            else:
                ws_display = f"WS {ws_name}"

            ws_badge = Gtk.Label(label=ws_display)
            ws_badge.get_style_context().add_class("ws-badge")
            ws_badge.set_halign(Gtk.Align.END)
            top_row.pack_end(ws_badge, False, False, 0)
            inner.pack_start(top_row, False, False, 0)

            # Center: Large application icon
            pix = resolve_icon(w.get('class'), w.get('title'), size=72)
            if pix:
                icon_img = Gtk.Image.new_from_pixbuf(pix)
            else:
                icon_img = Gtk.Image.new_from_icon_name("application-x-executable", Gtk.IconSize.DIALOG)
            icon_img.set_margin_top(14)
            icon_img.set_margin_bottom(10)
            inner.pack_start(icon_img, True, True, 0)

            # Bottom: Friendly application name
            app_lbl = Gtk.Label(label=resolve_app_name(w.get('class')))
            app_lbl.get_style_context().add_class("app-name")
            app_lbl.set_halign(Gtk.Align.CENTER)
            inner.pack_end(app_lbl, False, False, 0)

            card.add(inner)
            self.cards_box.pack_start(card, False, False, 0)
            self.cards.append(inner)

        self._update_highlight(scroll_only=True)

    def _update_highlight(self, scroll_only=False):
        if not self.windows:
            return

        sel_win = self.windows[self.selected_idx]
        title_text = sel_win.get('title', '')
        ws_name = str(sel_win.get('workspace', {}).get('name', ''))
        app_name = resolve_app_name(sel_win.get('class'))
        self.summary_title.set_text(f"{app_name}  —  {title_text}")

        for i, card_box in enumerate(self.cards):
            ctx = card_box.get_style_context()
            if i == self.selected_idx:
                ctx.add_class("active")
            else:
                ctx.remove_class("active")

        # Smoothly scroll active card into view
        GLib.idle_add(self._scroll_active_card)

    def _scroll_active_card(self):
        if not self.cards or self.selected_idx >= len(self.cards):
            return False
        card = self.cards[self.selected_idx]
        alloc = card.get_allocation()
        hadj = self.scrolled.get_hadjustment()
        if hadj and alloc.width > 0:
            view_width = self.scrolled.get_allocation().width
            target = alloc.x - (view_width / 2) + (alloc.width / 2)
            hadj.set_value(max(0, min(target, hadj.get_upper() - hadj.get_page_size())))
        return False

    def commit(self):
        if self.state != "SWITCHING":
            return
        self.state = "COMMITTING"
        self.win.hide()

        if self.windows and self.selected_idx < len(self.windows):
            target = self.windows[self.selected_idx]
            self._focus_window(target)

        self.state = "IDLE"

    def cancel(self):
        if self.state != "SWITCHING":
            return
        self.state = "IDLE"
        self.win.hide()
        if self.original_focused_addr:
            try:
                subprocess.run(
                    ['hyprctl', 'dispatch', 'focuswindow', f'address:{self.original_focused_addr}'],
                    check=False
                )
            except Exception:
                pass

    def _focus_window(self, target):
        addr = target.get('address')
        ws = target.get('workspace', {})
        ws_name = str(ws.get('name', ''))
        ws_id = ws.get('id', 1)

        try:
            if ws_name.startswith('special:minimized'):
                # Restore minimized window to current active workspace
                cur_raw = subprocess.check_output(['hyprctl', '-j', 'activeworkspace'], text=True)
                cur_ws_id = json.loads(cur_raw).get('id', 1)
                subprocess.run(['hyprctl', 'dispatch', 'movetoworkspace', f'{cur_ws_id},address:{addr}'], check=False)
                subprocess.run(['hyprctl', 'dispatch', 'focuswindow', f'address:{addr}'], check=False)
            elif ws_name.startswith('special:'):
                sp_name = ws_name.replace('special:', '', 1)
                subprocess.run(['hyprctl', 'dispatch', 'togglespecialworkspace', sp_name], check=False)
                subprocess.run(['hyprctl', 'dispatch', 'focuswindow', f'address:{addr}'], check=False)
            else:
                # Switch workspace first if on a different workspace
                if ws_id > 0:
                    subprocess.run(['hyprctl', 'dispatch', 'workspace', str(ws_id)], check=False)
                subprocess.run(['hyprctl', 'dispatch', 'focuswindow', f'address:{addr}'], check=False)
        except Exception as e:
            print("Error focusing window:", e, file=sys.stderr)

    def _on_key_press(self, widget, event):
        keyname = Gdk.keyval_name(event.keyval)
        if not keyname:
            return False

        if keyname == "Escape":
            self.cancel()
            return True
        elif keyname in ("Tab", "ISO_Left_Tab"):
            if event.state & Gdk.ModifierType.SHIFT_MASK:
                self.advance(-1)
            else:
                self.advance(1)
            return True
        elif keyname in ("Right", "Down"):
            self.advance(1)
            return True
        elif keyname in ("Left", "Up"):
            self.advance(-1)
            return True
        elif keyname in ("Return", "KP_Enter", "space"):
            self.commit()
            return True
        elif keyname in ("1", "2", "3", "4", "5", "6", "7", "8", "9"):
            idx = int(keyname) - 1
            if idx < len(self.windows):
                self.selected_idx = idx
                self.commit()
            return True
        return False

    def _on_key_release(self, widget, event):
        keyname = Gdk.keyval_name(event.keyval)
        if not keyname:
            return False

        # When modifier is released, commit switch!
        if keyname in ("Alt_L", "Alt_R", "Super_L", "Super_R", "Meta_L", "Meta_R"):
            self.commit()
            return True
        return False

    def _on_card_clicked(self, widget, event, idx):
        self.selected_idx = idx
        self.commit()
        return True

    def _on_card_hover(self, widget, event, idx):
        if self.state == "SWITCHING" and self.selected_idx != idx:
            self.selected_idx = idx
            self._update_highlight()
        return False

    def _on_backdrop_clicked(self, widget, event):
        self.cancel()
        return True


def run_client(command="NEXT"):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(SOCKET_PATH)
        s.sendall(f"{command}\n".encode())
        resp = s.recv(1024)
        if resp:
            text = resp.decode('utf-8').strip()
            if text and text != "OK":
                print(text)
        s.close()
        return True
    except Exception:
        return False


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "next"
    arg_lower = arg.lower()

    if arg_lower == "daemon":
        # Clean up socket on exit
        def cleanup():
            try:
                if os.path.exists(SOCKET_PATH):
                    os.unlink(SOCKET_PATH)
            except Exception:
                pass
        atexit.register(cleanup)
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, lambda s, f: sys.exit(0))

        daemon = WindowSwitcherDaemon()
        Gtk.main()
    else:
        # Client mode: map argument to command
        cmd_map = {
            "next": "NEXT",
            "prev": "PREV",
            "close": "CLOSE",
            "cancel": "CANCEL",
            "status": "STATUS",
            "quit": "QUIT"
        }
        cmd = cmd_map.get(arg_lower, "NEXT")
        success = run_client(cmd)
        if not success:
            # If daemon not running, launch daemon in background and retry
            script_path = os.path.abspath(__file__)
            subprocess.Popen([sys.executable, script_path, "daemon"], start_new_session=True)
            # Give daemon 0.15s to start and retry
            for _ in range(15):
                time.sleep(0.02)
                if run_client(cmd):
                    break


if __name__ == "__main__":
    main()
