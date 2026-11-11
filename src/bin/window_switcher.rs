// src/bin/window_switcher.rs
// Liquid Glass macOS-inspired Alt+Tab Window Switcher for Hyprland.
// Written in Rust with GTK4 and GTK4 Layer Shell.

use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::Command;
use std::rc::Rc;
use std::thread;
use std::time::{Duration, Instant};

use gdk4::prelude::*;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use serde::{Deserialize, Serialize};

thread_local! {
    static APP_INSTANCE: RefCell<Option<Rc<RefCell<SwitcherApp>>>> = const { RefCell::new(None) };
}

const CSS: &str = r#"
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
"#;

fn get_socket_path() -> PathBuf {
    let uid = unsafe { libc::getuid() };
    PathBuf::from(format!("/run/user/{}/hypr-window-switcher.sock", uid))
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct HyprWorkspace {
    id: i32,
    name: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct HyprClient {
    address: String,
    mapped: Option<bool>,
    title: Option<String>,
    class: Option<String>,
    swallowing: Option<String>,
    #[serde(rename = "focusHistoryID")]
    focus_history_id: Option<i64>,
    workspace: HyprWorkspace,
    pid: Option<i32>,
}

#[derive(Debug, Clone, Deserialize)]
struct ActiveWindow {
    address: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct ActiveWorkspace {
    id: i32,
}

#[derive(Clone)]
struct DesktopEntry {
    icon: Option<String>,
    name: Option<String>,
}

fn build_desktop_map() -> HashMap<String, DesktopEntry> {
    let mut map = HashMap::new();
    let dirs = vec![
        PathBuf::from("/usr/share/applications"),
        dirs_home_applications(),
    ];

    for dir in dirs {
        if !dir.exists() {
            continue;
        }
        let pattern = format!("{}/*.desktop", dir.to_string_lossy());
        if let Ok(paths) = glob::glob(&pattern) {
            for entry in paths.flatten() {
                if let Ok(file) = fs::File::open(&entry) {
                    let reader = BufReader::new(file);
                    let mut wm_class = None;
                    let mut icon = None;
                    let mut name = None;

                    for line in reader.lines().flatten() {
                        if line.starts_with("StartupWMClass=") {
                            wm_class = Some(line["StartupWMClass=".len()..].trim().to_string());
                        } else if line.starts_with("Icon=") && icon.is_none() {
                            icon = Some(line["Icon=".len()..].trim().to_string());
                        } else if line.starts_with("Name=") && name.is_none() {
                            name = Some(line["Name=".len()..].trim().to_string());
                        }
                    }

                    let file_stem = entry
                        .file_stem()
                        .map(|s| s.to_string_lossy().to_string().to_lowercase());

                    let d_entry = DesktopEntry {
                        icon: icon.clone(),
                        name: name.clone(),
                    };

                    if let Some(stem) = file_stem {
                        map.insert(stem, d_entry.clone());
                    }
                    if let Some(cl) = wm_class {
                        map.insert(cl.to_lowercase(), d_entry);
                    }
                }
            }
        }
    }
    map
}

fn dirs_home_applications() -> PathBuf {
    if let Ok(home) = env::var("HOME") {
        PathBuf::from(home).join(".local/share/applications")
    } else {
        PathBuf::from("/root/.local/share/applications")
    }
}

fn resolve_app_name(wm_class: &str, desktop_map: &HashMap<String, DesktopEntry>) -> String {
    if wm_class.is_empty() {
        return "Application".to_string();
    }
    let lower = wm_class.to_lowercase();
    if let Some(entry) = desktop_map.get(&lower) {
        if let Some(ref n) = entry.name {
            if !n.is_empty() {
                return n.clone();
            }
        }
    }
    let parts: Vec<&str> = wm_class.split('.').collect();
    if let Some(last) = parts.last() {
        let mut c = last.chars();
        match c.next() {
            None => "Application".to_string(),
            Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        }
    } else {
        "Application".to_string()
    }
}

fn resolve_icon_name(wm_class: &str, desktop_map: &HashMap<String, DesktopEntry>) -> String {
    let theme = gtk4::IconTheme::for_display(&gdk4::Display::default().unwrap_or_else(|| {
        panic!("No default display found");
    }));

    let mut candidates = Vec::new();
    if !wm_class.is_empty() {
        let lower = wm_class.to_lowercase();
        candidates.push(wm_class.to_string());
        candidates.push(lower.clone());

        if let Some(entry) = desktop_map.get(&lower) {
            if let Some(ref ic) = entry.icon {
                candidates.push(ic.clone());
            }
        }

        let parts: Vec<&str> = wm_class.split('.').collect();
        if parts.len() > 1 {
            if let Some(last) = parts.last() {
                candidates.push(last.to_lowercase());
                candidates.push(last.to_string());
            }
        }
    }

    candidates.push("application-x-executable".to_string());
    candidates.push("window-new".to_string());

    for cand in candidates {
        if theme.has_icon(&cand) {
            return cand;
        }
    }

    "application-x-executable".to_string()
}

#[derive(PartialEq, Eq)]
enum DaemonState {
    Idle,
    Switching,
    Committing,
}

struct SwitcherApp {
    state: DaemonState,
    windows: Vec<HyprClient>,
    cards: Vec<gtk4::Box>,
    selected_idx: usize,
    original_focused_addr: Option<String>,
    last_advance_time: Instant,
    desktop_map: HashMap<String, DesktopEntry>,

    // GTK Widgets
    win: gtk4::ApplicationWindow,
    summary_title: gtk4::Label,
    cards_box: gtk4::Box,
    scrolled: gtk4::ScrolledWindow,
}

impl SwitcherApp {
    fn new(app: &gtk4::Application) -> Rc<RefCell<Self>> {
        let win = gtk4::ApplicationWindow::new(app);
        win.init_layer_shell();
        win.set_layer(Layer::Overlay);
        win.set_anchor(Edge::Top, true);
        win.set_anchor(Edge::Bottom, true);
        win.set_anchor(Edge::Left, true);
        win.set_anchor(Edge::Right, true);
        win.set_keyboard_mode(KeyboardMode::Exclusive);
        win.set_namespace("window-switcher");

        let backdrop = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        backdrop.set_widget_name("backdrop");
        backdrop.set_hexpand(true);
        backdrop.set_vexpand(true);

        let center_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        center_box.set_halign(gtk4::Align::Center);
        center_box.set_valign(gtk4::Align::Center);
        center_box.set_hexpand(true);
        center_box.set_vexpand(true);

        let container = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        container.set_widget_name("switcher-container");

        // Summary Bar
        let summary_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
        summary_box.set_widget_name("summary-bar");

        let summary_title = gtk4::Label::new(None);
        summary_title.set_widget_name("summary-title");
        summary_title.set_halign(gtk4::Align::Start);
        summary_title.set_ellipsize(gtk4::pango::EllipsizeMode::End);
        summary_title.set_max_width_chars(52);
        summary_title.set_hexpand(true);
        summary_box.append(&summary_title);

        let summary_hint = gtk4::Label::new(Some(
            "Tab 󰌑 Next  ·  ⇧Tab Prev  ·  Release 󰘵 Select  ·  Esc Cancel",
        ));
        summary_hint.set_widget_name("summary-hint");
        summary_hint.set_halign(gtk4::Align::End);
        summary_box.append(&summary_hint);

        container.append(&summary_box);

        // Scrolled Window & Cards Box
        let scrolled = gtk4::ScrolledWindow::new();
        scrolled.set_policy(gtk4::PolicyType::Automatic, gtk4::PolicyType::Never);
        scrolled.set_has_frame(false);

        let cards_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
        cards_box.set_halign(gtk4::Align::Center);
        scrolled.set_child(Some(&cards_box));

        container.append(&scrolled);
        center_box.append(&container);
        backdrop.append(&center_box);
        win.set_child(Some(&backdrop));

        // Prevent click inside container from dismissing
        let container_click = gtk4::GestureClick::new();
        container_click.connect_pressed(|ctrl, _, _, _| {
            ctrl.set_state(gtk4::EventSequenceState::Claimed);
        });
        container.add_controller(container_click);

        let desktop_map = build_desktop_map();

        let app_rc = Rc::new(RefCell::new(Self {
            state: DaemonState::Idle,
            windows: Vec::new(),
            cards: Vec::new(),
            selected_idx: 0,
            original_focused_addr: None,
            last_advance_time: Instant::now() - Duration::from_secs(10),
            desktop_map,
            win: win.clone(),
            summary_title,
            cards_box,
            scrolled,
        }));

        // Click on backdrop cancels
        let click_ctrl = gtk4::GestureClick::new();
        let app_weak = Rc::downgrade(&app_rc);
        click_ctrl.connect_pressed(move |_, _, _, _| {
            if let Some(app) = app_weak.upgrade() {
                app.borrow_mut().cancel();
            }
        });
        backdrop.add_controller(click_ctrl);

        // Keyboard Controller
        let key_ctrl = gtk4::EventControllerKey::new();
        let app_weak2 = Rc::downgrade(&app_rc);
        key_ctrl.connect_key_pressed(move |_, key, _, modifier| {
            if let Some(app) = app_weak2.upgrade() {
                let mut a = app.borrow_mut();
                match key {
                    gdk4::Key::Escape => {
                        a.cancel();
                        glib::Propagation::Stop
                    }
                    gdk4::Key::Tab | gdk4::Key::ISO_Left_Tab => {
                        let step = if modifier.contains(gdk4::ModifierType::SHIFT_MASK) {
                            -1
                        } else {
                            1
                        };
                        a.advance(step);
                        glib::Propagation::Stop
                    }
                    gdk4::Key::Right | gdk4::Key::Down => {
                        a.advance(1);
                        glib::Propagation::Stop
                    }
                    gdk4::Key::Left | gdk4::Key::Up => {
                        a.advance(-1);
                        glib::Propagation::Stop
                    }
                    gdk4::Key::Return | gdk4::Key::KP_Enter | gdk4::Key::space => {
                        a.commit();
                        glib::Propagation::Stop
                    }
                    gdk4::Key::_1 | gdk4::Key::_2 | gdk4::Key::_3 | gdk4::Key::_4
                    | gdk4::Key::_5 | gdk4::Key::_6 | gdk4::Key::_7 | gdk4::Key::_8
                    | gdk4::Key::_9 => {
                        let idx = (key.to_unicode().unwrap_or('1') as usize) - ('1' as usize);
                        if idx < a.windows.len() {
                            a.selected_idx = idx;
                            a.commit();
                        }
                        glib::Propagation::Stop
                    }
                    _ => glib::Propagation::Proceed,
                }
            } else {
                glib::Propagation::Proceed
            }
        });

        // Key release commits focus when Alt or Super modifier is released
        let app_weak3 = Rc::downgrade(&app_rc);
        key_ctrl.connect_key_released(move |_, key, _, _| {
            if let Some(app) = app_weak3.upgrade() {
                match key {
                    gdk4::Key::Alt_L
                    | gdk4::Key::Alt_R
                    | gdk4::Key::Super_L
                    | gdk4::Key::Super_R
                    | gdk4::Key::Meta_L
                    | gdk4::Key::Meta_R => {
                        app.borrow_mut().commit();
                    }
                    _ => {}
                }
            }
        });
        win.add_controller(key_ctrl);

        app_rc
    }

    fn query_eligible_windows(&self) -> (Vec<HyprClient>, Option<String>) {
        let clients_raw = Command::new("hyprctl")
            .args(["-j", "clients"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_default();

        let clients: Vec<HyprClient> = serde_json::from_str(&clients_raw).unwrap_or_default();

        let active_raw = Command::new("hyprctl")
            .args(["-j", "activewindow"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_default();

        let active: Option<ActiveWindow> = serde_json::from_str(&active_raw).ok();
        let active_addr = active.and_then(|a| a.address);

        let mut eligible: Vec<HyprClient> = clients
            .into_iter()
            .filter(|c| {
                if !c.mapped.unwrap_or(true) {
                    return false;
                }
                let title = c.title.as_deref().unwrap_or("").trim();
                let class = c.class.as_deref().unwrap_or("").trim();
                if title.is_empty() && class.is_empty() {
                    return false;
                }
                if class == "hypr-window-switcher" || class == "audio-switcher" {
                    return false;
                }
                if let Some(ref sw) = c.swallowing {
                    if !sw.is_empty() && sw != "0x0" {
                        return false;
                    }
                }
                true
            })
            .collect();

        // Sort MRU by focusHistoryID (0 = current, 1 = previous, etc.)
        eligible.sort_by_key(|c| {
            let fhid = c.focus_history_id.unwrap_or(-1);
            if fhid >= 0 {
                (0, fhid, c.workspace.id, c.pid.unwrap_or(0))
            } else {
                (1, 9999, c.workspace.id, c.pid.unwrap_or(0))
            }
        });

        // Ensure active window is at index 0 if found
        if let Some(ref addr) = active_addr {
            if let Some(pos) = eligible.iter().position(|c| &c.address == addr) {
                if pos != 0 {
                    let act = eligible.remove(pos);
                    eligible.insert(0, act);
                }
            }
        }

        (eligible, active_addr)
    }

    fn advance(&mut self, step: i32) {
        let now = Instant::now();
        if self.state == DaemonState::Switching && now.duration_since(self.last_advance_time) < Duration::from_millis(65) {
            return;
        }
        self.last_advance_time = now;

        if self.state == DaemonState::Idle {
            let (windows, original_addr) = self.query_eligible_windows();
            if windows.is_empty() {
                return;
            }

            self.windows = windows;
            self.original_focused_addr = original_addr;

            if self.windows.len() == 1 {
                self.selected_idx = 0;
            } else if step >= 0 {
                self.selected_idx = 1;
            } else {
                self.selected_idx = self.windows.len() - 1;
            }

            self.build_ui();
            self.state = DaemonState::Switching;
            self.win.present();
        } else {
            if self.windows.is_empty() {
                return;
            }
            let len = self.windows.len() as i32;
            let mut next = (self.selected_idx as i32 + step) % len;
            if next < 0 {
                next += len;
            }
            self.selected_idx = next as usize;
            self.update_highlight();
        }
    }

    fn build_ui(&mut self) {
        while let Some(child) = self.cards_box.first_child() {
            self.cards_box.remove(&child);
        }
        self.cards.clear();

        for (i, w) in self.windows.iter().enumerate() {
            let card_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
            card_box.add_css_class("window-card");
            if i == self.selected_idx {
                card_box.add_css_class("active");
            }

            // Top Row: Title + WS Badge
            let top_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
            let title_text = w.title.as_deref().unwrap_or("Window");
            let card_title = gtk4::Label::new(Some(title_text));
            card_title.add_css_class("card-title");
            card_title.set_halign(gtk4::Align::Start);
            card_title.set_ellipsize(gtk4::pango::EllipsizeMode::End);
            card_title.set_max_width_chars(15);
            card_title.set_hexpand(true);
            top_row.append(&card_title);

            let ws_name = &w.workspace.name;
            let ws_display = if ws_name.starts_with("special:minimized") {
                "Min".to_string()
            } else if ws_name.starts_with("special:") {
                let rest = ws_name.strip_prefix("special:").unwrap_or("");
                let cap = rest.chars().take(4).collect::<String>();
                format!("Sp:{}", cap)
            } else {
                format!("WS {}", ws_name)
            };

            let ws_badge = gtk4::Label::new(Some(&ws_display));
            ws_badge.add_css_class("ws-badge");
            ws_badge.set_halign(gtk4::Align::End);
            top_row.append(&ws_badge);
            card_box.append(&top_row);

            // Large Center Icon (72px)
            let wm_class = w.class.as_deref().unwrap_or("");
            let icon_name = resolve_icon_name(wm_class, &self.desktop_map);
            let icon_img = gtk4::Image::from_icon_name(&icon_name);
            icon_img.set_pixel_size(72);
            icon_img.set_margin_top(14);
            icon_img.set_margin_bottom(10);
            icon_img.set_vexpand(true);
            card_box.append(&icon_img);

            // Bottom App Name
            let app_name = resolve_app_name(wm_class, &self.desktop_map);
            let app_lbl = gtk4::Label::new(Some(&app_name));
            app_lbl.add_css_class("app-name");
            app_lbl.set_halign(gtk4::Align::Center);
            card_box.append(&app_lbl);

            // Click on card commits to that window
            let click = gtk4::GestureClick::new();
            click.connect_pressed(move |_, _, _, _| {
                APP_INSTANCE.with(|inst| {
                    if let Some(ref a) = *inst.borrow() {
                        let mut sw = a.borrow_mut();
                        sw.selected_idx = i;
                        sw.commit();
                    }
                });
            });
            card_box.add_controller(click);

            // Hover updates active selection
            let motion = gtk4::EventControllerMotion::new();
            motion.connect_enter(move |_, _, _| {
                APP_INSTANCE.with(|inst| {
                    if let Some(ref a) = *inst.borrow() {
                        let mut sw = a.borrow_mut();
                        if sw.state == DaemonState::Switching && sw.selected_idx != i {
                            sw.selected_idx = i;
                            sw.update_highlight();
                        }
                    }
                });
            });
            card_box.add_controller(motion);

            self.cards_box.append(&card_box);
            self.cards.push(card_box);
        }

        self.update_highlight();
    }

    fn update_highlight(&self) {
        if self.windows.is_empty() {
            return;
        }

        let sel_win = &self.windows[self.selected_idx];
        let title_text = sel_win.title.as_deref().unwrap_or("");
        let wm_class = sel_win.class.as_deref().unwrap_or("");
        let app_name = resolve_app_name(wm_class, &self.desktop_map);
        self.summary_title
            .set_text(&format!("{}  —  {}", app_name, title_text));

        for (i, card_box) in self.cards.iter().enumerate() {
            if i == self.selected_idx {
                card_box.add_css_class("active");
            } else {
                card_box.remove_css_class("active");
            }
        }

        // Center the active card in the scroll area
        if let Some(card) = self.cards.get(self.selected_idx) {
            let hadj = self.scrolled.hadjustment();
            let view_width = self.scrolled.width() as f64;
            let card_width = card.width() as f64;
            let card_x = (self.selected_idx as f64) * (card_width + 10.0);
            let target = card_x - (view_width / 2.0) + (card_width / 2.0);
            let max_val = hadj.upper() - hadj.page_size();
            hadj.set_value(target.clamp(0.0, max_val.max(0.0)));
        }
    }

    fn commit(&mut self) {
        if self.state != DaemonState::Switching {
            return;
        }
        self.state = DaemonState::Committing;
        self.win.set_visible(false);

        if !self.windows.is_empty() && self.selected_idx < self.windows.len() {
            let target = self.windows[self.selected_idx].clone();
            self.focus_window(&target);
        }

        self.state = DaemonState::Idle;
    }

    fn cancel(&mut self) {
        if self.state != DaemonState::Switching {
            return;
        }
        self.state = DaemonState::Idle;
        self.win.set_visible(false);

        if let Some(ref addr) = self.original_focused_addr {
            let _ = Command::new("hyprctl")
                .args(["dispatch", "focuswindow", &format!("address:{}", addr)])
                .status();
        }
    }

    fn focus_window(&self, target: &HyprClient) {
        let addr = &target.address;
        let ws_name = &target.workspace.name;
        let ws_id = target.workspace.id;

        if ws_name.starts_with("special:minimized") {
            let cur_raw = Command::new("hyprctl")
                .args(["-j", "activeworkspace"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            let cur: ActiveWorkspace = serde_json::from_str(&cur_raw).unwrap_or(ActiveWorkspace { id: 1 });
            let _ = Command::new("hyprctl")
                .args(["dispatch", "movetoworkspace", &format!("{},address:{}", cur.id, addr)])
                .status();
            let _ = Command::new("hyprctl")
                .args(["dispatch", "focuswindow", &format!("address:{}", addr)])
                .status();
        } else if ws_name.starts_with("special:") {
            let sp_name = ws_name.strip_prefix("special:").unwrap_or("");
            let _ = Command::new("hyprctl")
                .args(["dispatch", "togglespecialworkspace", sp_name])
                .status();
            let _ = Command::new("hyprctl")
                .args(["dispatch", "focuswindow", &format!("address:{}", addr)])
                .status();
        } else {
            if ws_id > 0 {
                let _ = Command::new("hyprctl")
                    .args(["dispatch", "workspace", &ws_id.to_string()])
                    .status();
            }
            let _ = Command::new("hyprctl")
                .args(["dispatch", "focuswindow", &format!("address:{}", addr)])
                .status();
        }
    }
}

fn run_client(cmd: &str) -> bool {
    let sock_path = get_socket_path();
    if let Ok(mut stream) = UnixStream::connect(&sock_path) {
        let _ = stream.write_all(format!("{}\n", cmd).as_bytes());
        let mut buf = [0u8; 1024];
        if let Ok(n) = stream.read(&mut buf) {
            if n > 0 {
                let resp = String::from_utf8_lossy(&buf[..n]);
                let trimmed = resp.trim();
                if !trimmed.is_empty() && trimmed != "OK" {
                    println!("{}", trimmed);
                }
            }
        }
        true
    } else {
        false
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let action = args.get(1).map(|s| s.as_str()).unwrap_or("next");

    if action.eq_ignore_ascii_case("daemon") || action.eq_ignore_ascii_case("init") {
        let app = gtk4::Application::new(
            Some("com.hypercli.window_switcher"),
            gio::ApplicationFlags::empty(),
        );

        app.connect_startup(|_| {
            if let Some(display) = gdk4::Display::default() {
                let provider = gtk4::CssProvider::new();
                provider.load_from_data(CSS);
                gtk4::style_context_add_provider_for_display(
                    &display,
                    &provider,
                    gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
                );
            }
        });

        app.connect_activate(move |app| {
            let switcher = SwitcherApp::new(app);
            APP_INSTANCE.with(|inst| {
                *inst.borrow_mut() = Some(switcher);
            });

            let sock_path = get_socket_path();
            if sock_path.exists() {
                let _ = fs::remove_file(&sock_path);
            }

            let listener = UnixListener::bind(&sock_path).expect("Failed to bind UNIX socket");

            // Background thread to listen on Unix socket
            thread::spawn(move || {
                for stream in listener.incoming().flatten() {
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    let mut line = String::new();
                    if reader.read_line(&mut line).is_ok() {
                        let cmd_str = line.trim().to_uppercase();
                        let mut stream_opt = Some(stream);

                        glib::idle_add_once(move || {
                            APP_INSTANCE.with(|inst| {
                                if let Some(ref a) = *inst.borrow() {
                                    let mut sw = a.borrow_mut();
                                    match cmd_str.as_str() {
                                        "NEXT" => {
                                            sw.advance(1);
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"OK\n");
                                            }
                                        }
                                        "PREV" => {
                                            sw.advance(-1);
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"OK\n");
                                            }
                                        }
                                        "CLOSE" => {
                                            sw.commit();
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"OK\n");
                                            }
                                        }
                                        "CANCEL" => {
                                            sw.cancel();
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"OK\n");
                                            }
                                        }
                                        "STATUS" => {
                                            if let Some(mut s) = stream_opt.take() {
                                                let state_str = match sw.state {
                                                    DaemonState::Idle => "IDLE",
                                                    DaemonState::Switching => "SWITCHING",
                                                    DaemonState::Committing => "COMMITTING",
                                                };
                                                let resp = serde_json::json!({
                                                    "state": state_str,
                                                    "windows": sw.windows.len(),
                                                    "selected": sw.selected_idx
                                                });
                                                let _ = s.write_all(format!("{}\n", resp).as_bytes());
                                            }
                                        }
                                        "QUIT" => {
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"BYE\n");
                                            }
                                            std::process::exit(0);
                                        }
                                        _ => {
                                            sw.advance(1);
                                            if let Some(mut s) = stream_opt.take() {
                                                let _ = s.write_all(b"OK\n");
                                            }
                                        }
                                    }
                                }
                            });
                        });
                    }
                }
            });
        });

        let empty_args: Vec<String> = vec![];
        app.run_with_args(&empty_args);
    } else {
        // Client Mode
        let cmd = match action.to_lowercase().as_str() {
            "next" => "NEXT",
            "prev" => "PREV",
            "close" => "CLOSE",
            "cancel" => "CANCEL",
            "status" => "STATUS",
            "quit" => "QUIT",
            _ => "NEXT",
        };

        if !run_client(cmd) {
            // Daemon not running, spawn it in background and retry
            let exe = env::current_exe().unwrap_or_else(|_| PathBuf::from("window-switcher"));
            let _ = Command::new(&exe)
                .arg("daemon")
                .spawn();

            for _ in 0..15 {
                thread::sleep(Duration::from_millis(25));
                if run_client(cmd) {
                    break;
                }
            }
        }
    }
}
