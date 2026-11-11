// src/bin/audio_switcher_popup.rs
// Modern Control Center style Audio Output Switcher popup for Hyprland & Waybar.
// Written in Rust with GTK4 and GTK4 Layer Shell.

use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use gdk4::prelude::*;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use serde_json::Value;

static WAYBAR_PINNED_ACTIVE: AtomicBool = AtomicBool::new(false);

struct WaybarPinner;

impl WaybarPinner {
    fn pin() {
        let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        let pinned_file = PathBuf::from(&runtime_dir).join("waybar-pinned");
        let pid_file = PathBuf::from(&runtime_dir).join("waybar-autohide.pid");

        if let Ok(mut f) = fs::File::create(&pinned_file) {
            let _ = f.write_all(b"1\n");
            WAYBAR_PINNED_ACTIVE.store(true, Ordering::SeqCst);
        }

        if pid_file.exists() {
            if let Ok(content) = fs::read_to_string(&pid_file) {
                if let Ok(pid) = content.trim().parse::<i32>() {
                    unsafe {
                        libc::kill(pid, libc::SIGUSR2);
                    }
                }
            }
        }
    }

    fn unpin() {
        if !WAYBAR_PINNED_ACTIVE.swap(false, Ordering::SeqCst) {
            return;
        }
        let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        let pinned_file = PathBuf::from(&runtime_dir).join("waybar-pinned");
        let pid_file = PathBuf::from(&runtime_dir).join("waybar-autohide.pid");

        let _ = fs::remove_file(&pinned_file);

        if pid_file.exists() {
            if let Ok(content) = fs::read_to_string(&pid_file) {
                if let Ok(pid) = content.trim().parse::<i32>() {
                    unsafe {
                        libc::kill(pid, libc::SIGUSR2);
                    }
                }
            }
        }
    }
}

impl Drop for WaybarPinner {
    fn drop(&mut self) {
        WaybarPinner::unpin();
    }
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
"#;

#[derive(Clone, Debug)]
enum AudioAction {
    Sink {
        name: String,
        object_id: Option<String>,
    },
    Profile {
        card: String,
        profile: String,
        sink_pattern: String,
    },
}

#[derive(Clone, Debug)]
struct AudioTarget {
    name: String,
    subtitle: String,
    icon: String,
    is_active: bool,
    action: AudioAction,
}

fn detect_audio_targets() -> Vec<AudioTarget> {
    let def_sink = Command::new("pactl")
        .arg("get-default-sink")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default();

    let sinks_val: Value = Command::new("pactl")
        .args(["-f", "json", "list", "sinks"])
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice(&o.stdout).ok())
        .unwrap_or(Value::Array(vec![]));

    let cards_val: Value = Command::new("pactl")
        .args(["-f", "json", "list", "cards"])
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice(&o.stdout).ok())
        .unwrap_or(Value::Array(vec![]));

    let sinks = sinks_val.as_array().cloned().unwrap_or_default();
    let cards = cards_val.as_array().cloned().unwrap_or_default();

    let mut targets = Vec::new();
    let mut seen_keys = std::collections::HashSet::new();

    // 1. Connected Bluetooth sinks
    for s in &sinks {
        let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let props = s.get("properties");
        let bus = props
            .and_then(|p| p.get("device.bus"))
            .and_then(|b| b.as_str())
            .unwrap_or("");
        let desc = s
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or(name);

        if bus == "bluetooth" || name.to_lowercase().contains("bluez") {
            let key = format!("sink:{}", name);
            seen_keys.insert(key);
            let object_id = props
                .and_then(|p| p.get("object.id"))
                .and_then(|id| id.as_str().or_else(|| id.as_i64().map(|_| "")))
                .map(|s| s.to_string());

            targets.push(AudioTarget {
                name: desc.to_string(),
                subtitle: "Bluetooth Audio".to_string(),
                icon: "󰥰".to_string(),
                is_active: name == def_sink,
                action: AudioAction::Sink {
                    name: name.to_string(),
                    object_id,
                },
            });
        }
    }

    // 2. Built-in Card Profiles (Speakers and Wired Headphones)
    for c in &cards {
        let cname = c.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let active_prof = c
            .get("active_profile")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let profiles = c.get("profiles").and_then(|v| v.as_object());

        let mut speaker_prof = None;
        let mut headphones_prof = None;

        if let Some(profs) = profiles {
            for pname in profs.keys() {
                if pname.contains("Speaker") && speaker_prof.is_none() {
                    speaker_prof = Some(pname.clone());
                } else if pname.contains("Headphone") && headphones_prof.is_none() {
                    headphones_prof = Some(pname.clone());
                }
            }
        }

        if let Some(sp) = speaker_prof {
            let is_active = def_sink.contains("Speaker")
                || (active_prof.contains("Speaker")
                    && !def_sink.contains("bluez")
                    && !def_sink.contains("HDMI"));
            targets.push(AudioTarget {
                name: "Internal Speakers".to_string(),
                subtitle: "Built-in Audio".to_string(),
                icon: "󰓃".to_string(),
                is_active,
                action: AudioAction::Profile {
                    card: cname.to_string(),
                    profile: sp,
                    sink_pattern: "Speaker".to_string(),
                },
            });
        }

        if let Some(hp) = headphones_prof {
            let is_active = def_sink.contains("Headphone")
                || (active_prof.contains("Headphone")
                    && !def_sink.contains("bluez")
                    && !def_sink.contains("HDMI"));
            targets.push(AudioTarget {
                name: "Wired Headphones".to_string(),
                subtitle: "3.5mm Audio Jack".to_string(),
                icon: "󰋋".to_string(),
                is_active,
                action: AudioAction::Profile {
                    card: cname.to_string(),
                    profile: hp,
                    sink_pattern: "Headphone".to_string(),
                },
            });
        }
    }

    // 3. Connected external displays / HDMI
    for s in &sinks {
        let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let props = s.get("properties");
        let desc = s
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or(name);
        let ports = s
            .get("ports")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let has_avail = ports.iter().any(|p| {
            p.get("availability")
                .and_then(|a| a.as_str())
                .map(|a| a == "available")
                .unwrap_or(false)
        });

        let desc_lower = desc.to_lowercase();
        if (has_avail || ports.is_empty())
            && (desc_lower.contains("hdmi") || desc_lower.contains("displayport"))
        {
            let key = format!("sink:{}", name);
            if !seen_keys.contains(&key) {
                seen_keys.insert(key);
                let object_id = props
                    .and_then(|p| p.get("object.id"))
                    .map(|v| v.to_string());
                targets.push(AudioTarget {
                    name: "External Display".to_string(),
                    subtitle: "HDMI / DisplayPort".to_string(),
                    icon: "󰍹".to_string(),
                    is_active: name == def_sink,
                    action: AudioAction::Sink {
                        name: name.to_string(),
                        object_id,
                    },
                });
            }
        }
    }

    // 4. USB Audio DACs
    for s in &sinks {
        let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let props = s.get("properties");
        let bus = props
            .and_then(|p| p.get("device.bus"))
            .and_then(|b| b.as_str())
            .unwrap_or("");
        let desc = s
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or(name);

        if bus == "usb" {
            let key = format!("sink:{}", name);
            if !seen_keys.contains(&key) {
                seen_keys.insert(key);
                let object_id = props
                    .and_then(|p| p.get("object.id"))
                    .map(|v| v.to_string());
                targets.push(AudioTarget {
                    name: desc.to_string(),
                    subtitle: "USB Audio Device".to_string(),
                    icon: "󰓃".to_string(),
                    is_active: name == def_sink,
                    action: AudioAction::Sink {
                        name: name.to_string(),
                        object_id,
                    },
                });
            }
        }
    }

    targets
}

fn get_current_volume() -> (f32, bool) {
    if let Ok(output) = Command::new("wpctl")
        .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
        .output()
    {
        if let Ok(text) = String::from_utf8(output.stdout) {
            let parts: Vec<&str> = text.split_whitespace().collect();
            if parts.len() >= 2 {
                if let Ok(vol) = parts[1].parse::<f32>() {
                    let muted = text.contains("[MUTED]");
                    return (vol, muted);
                }
            }
        }
    }
    (1.0, false)
}

fn move_all_streams(target_sink: &str) {
    if let Ok(output) = Command::new("pactl")
        .args(["-f", "json", "list", "sink-inputs"])
        .output()
    {
        if let Ok(inputs) = serde_json::from_slice::<Value>(&output.stdout) {
            if let Some(arr) = inputs.as_array() {
                for inp in arr {
                    if let Some(idx) = inp.get("index").and_then(|i| i.as_i64()) {
                        let _ = Command::new("pactl")
                            .args(["move-sink-input", &idx.to_string(), target_sink])
                            .status();
                    }
                }
            }
        }
    }
}

fn switch_audio(action: AudioAction) {
    let (cur_vol, cur_muted) = get_current_volume();
    let mut target_sink: Option<String> = None;
    let mut target_id: Option<String> = None;

    match action {
        AudioAction::Profile {
            card,
            profile,
            sink_pattern,
        } => {
            let _ = Command::new("pactl")
                .args(["set-card-profile", &card, &profile])
                .status();

            let pattern = sink_pattern.to_lowercase();
            let start = Instant::now();
            while start.elapsed() < Duration::from_millis(2000) {
                if let Ok(output) = Command::new("pactl")
                    .args(["-f", "json", "list", "sinks"])
                    .output()
                {
                    if let Ok(val) = serde_json::from_slice::<Value>(&output.stdout) {
                        if let Some(arr) = val.as_array() {
                            for s in arr {
                                let s_name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
                                let s_desc = s.get("description").and_then(|v| v.as_str()).unwrap_or("");
                                if s_name.to_lowercase().contains(&pattern)
                                    || s_desc.to_lowercase().contains(&pattern)
                                {
                                    target_sink = Some(s_name.to_string());
                                    target_id = s
                                        .get("properties")
                                        .and_then(|p| p.get("object.id"))
                                        .map(|v| v.to_string());
                                    break;
                                }
                            }
                        }
                    }
                }
                if target_sink.is_some() {
                    break;
                }
                thread::sleep(Duration::from_millis(20));
            }
        }
        AudioAction::Sink { name, object_id } => {
            target_sink = Some(name);
            target_id = object_id;
        }
    }

    if let Some(ref sink) = target_sink {
        let _ = Command::new("pactl")
            .args(["set-default-sink", sink])
            .status();

        if let Some(ref id) = target_id {
            let _ = Command::new("wpctl")
                .args(["set-default", id])
                .status();
        }

        move_all_streams(sink);

        let safe_vol = cur_vol.min(1.0);
        if let Some(ref id) = target_id {
            let _ = Command::new("wpctl")
                .args(["set-volume", id, &format!("{:.2}", safe_vol)])
                .status();
            let _ = Command::new("wpctl")
                .args(["set-mute", id, if cur_muted { "1" } else { "0" }])
                .status();
        } else {
            let _ = Command::new("pactl")
                .args(["set-sink-volume", sink, &format!("{}%", (safe_vol * 100.0) as i32)])
                .status();
            let _ = Command::new("pactl")
                .args(["set-sink-mute", sink, if cur_muted { "1" } else { "0" }])
                .status();
        }
    }

    // Trigger instant Waybar refresh (SIGRTMIN+8)
    let _ = Command::new("pkill")
        .args(["-RTMIN+8", "waybar"])
        .status();
}

extern "C" fn sig_handler(_: libc::c_int) {
    WaybarPinner::unpin();
    std::process::exit(0);
}

fn main() {
    unsafe {
        libc::signal(libc::SIGINT, sig_handler as *const () as usize);
        libc::signal(libc::SIGTERM, sig_handler as *const () as usize);
    }

    let _pinner = WaybarPinner;
    WaybarPinner::pin();

    let app = gtk4::Application::new(
        Some("com.hypercli.audio_switcher_popup"),
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

    app.connect_activate(|app| {
        let win = gtk4::ApplicationWindow::new(app);
        win.init_layer_shell();
        win.set_layer(Layer::Top);
        win.set_anchor(Edge::Top, true);
        win.set_anchor(Edge::Bottom, true);
        win.set_anchor(Edge::Left, true);
        win.set_anchor(Edge::Right, true);
        win.set_keyboard_mode(KeyboardMode::OnDemand);
        win.set_namespace("audio-switcher");

        // Transparent backdrop
        let backdrop = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        backdrop.set_widget_name("backdrop");
        backdrop.set_hexpand(true);
        backdrop.set_vexpand(true);

        let app_clone = app.clone();
        let click_ctrl = gtk4::GestureClick::new();
        click_ctrl.connect_pressed(move |_, _, _, _| {
            WaybarPinner::unpin();
            app_clone.quit();
        });
        backdrop.add_controller(click_ctrl);

        let outer_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        outer_box.set_halign(gtk4::Align::End);
        outer_box.set_valign(gtk4::Align::End);
        outer_box.set_margin_bottom(48);
        outer_box.set_margin_end(60);

        let card = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
        card.set_widget_name("card");
        card.set_size_request(280, -1);

        // Prevent click inside card from dismissing popup
        let card_click = gtk4::GestureClick::new();
        card_click.connect_pressed(|ctrl, _, _, _| {
            ctrl.set_state(gtk4::EventSequenceState::Claimed);
        });
        card.add_controller(card_click);

        // Header
        let hdr = gtk4::Label::new(Some("󰓃  Media Output"));
        hdr.set_widget_name("header-title");
        hdr.set_halign(gtk4::Align::Start);
        card.append(&hdr);

        let sub = gtk4::Label::new(Some("Select playback device"));
        sub.set_widget_name("header-subtitle");
        sub.set_halign(gtk4::Align::Start);
        card.append(&sub);

        let targets = detect_audio_targets();

        for dev in targets {
            let btn = gtk4::Button::new();
            btn.add_css_class("device-row");
            if dev.is_active {
                btn.add_css_class("active");
            }

            let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);

            let icon_lbl = gtk4::Label::new(Some(&dev.icon));
            icon_lbl.add_css_class("device-icon");
            if !dev.is_active {
                icon_lbl.add_css_class("inactive");
            }
            hbox.append(&icon_lbl);

            let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
            let name_lbl = gtk4::Label::new(Some(&dev.name));
            name_lbl.add_css_class("device-name");
            name_lbl.set_halign(gtk4::Align::Start);
            if dev.is_active {
                name_lbl.add_css_class("active");
            }
            vbox.append(&name_lbl);

            let desc_lbl = gtk4::Label::new(Some(&dev.subtitle));
            desc_lbl.add_css_class("device-desc");
            desc_lbl.set_halign(gtk4::Align::Start);
            if dev.is_active {
                desc_lbl.add_css_class("active");
            }
            vbox.append(&desc_lbl);
            vbox.set_hexpand(true);
            hbox.append(&vbox);

            if dev.is_active {
                let chk = gtk4::Label::new(Some("󰄬"));
                chk.add_css_class("check-icon");
                chk.set_halign(gtk4::Align::End);
                hbox.append(&chk);
            }

            btn.set_child(Some(&hbox));

            let action = dev.action.clone();
            let dev_name = dev.name.clone();
            let app_c = app.clone();
            btn.connect_clicked(move |_| {
                switch_audio(action.clone());
                let _ = Command::new("notify-send")
                    .args([
                        "-u",
                        "low",
                        "-i",
                        "audio-volume-high",
                        "Audio Output",
                        &format!("Switched to {}", dev_name),
                    ])
                    .status();
                WaybarPinner::unpin();
                app_c.quit();
            });

            card.append(&btn);
        }

        outer_box.append(&card);
        backdrop.append(&outer_box);
        win.set_child(Some(&backdrop));

        let app_c2 = app.clone();
        let key_ctrl = gtk4::EventControllerKey::new();
        key_ctrl.connect_key_pressed(move |_, key, _, _| {
            if key == gdk4::Key::Escape {
                WaybarPinner::unpin();
                app_c2.quit();
                glib::Propagation::Stop
            } else {
                glib::Propagation::Proceed
            }
        });
        win.add_controller(key_ctrl);

        win.present();
    });

    let empty_args: Vec<String> = vec![];
    app.run_with_args(&empty_args);
    WaybarPinner::unpin();
}
