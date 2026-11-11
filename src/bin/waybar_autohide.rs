// src/bin/waybar_autohide.rs
// Ultra-lightweight native Rust autohide daemon for Waybar & Hyprland.
// Communicates directly with Hyprland's IPC socket for sub-millisecond edge response
// with zero subshell/fork-exec overhead and near-zero CPU usage.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use serde_json::Value;

static RUNNING: AtomicBool = AtomicBool::new(true);
static FORCED_CHECK: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_term(_: libc::c_int) {
    RUNNING.store(false, Ordering::SeqCst);
}

extern "C" fn handle_usr2(_: libc::c_int) {
    FORCED_CHECK.store(true, Ordering::SeqCst);
}

fn get_hyprland_socket_path() -> Option<PathBuf> {
    let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let his = env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let path = PathBuf::from(runtime_dir).join("hypr").join(his).join(".socket.sock");
    if path.exists() {
        Some(path)
    } else {
        None
    }
}

fn get_cursor_pos(socket_path: &Path) -> Option<(i32, i32)> {
    let mut stream = UnixStream::connect(socket_path).ok()?;
    stream.write_all(b"cursorpos").ok()?;
    let mut resp = String::new();
    stream.read_to_string(&mut resp).ok()?;
    let mut parts = resp.trim().split(',');
    let x = parts.next()?.trim().parse::<i32>().ok()?;
    let y = parts.next()?.trim().parse::<i32>().ok()?;
    Some((x, y))
}

fn get_screen_height(socket_path: &Path) -> i32 {
    if let Ok(mut stream) = UnixStream::connect(socket_path) {
        if stream.write_all(b"j/monitors").is_ok() {
            let mut resp = String::new();
            if stream.read_to_string(&mut resp).is_ok() {
                if let Ok(v) = serde_json::from_str::<Value>(&resp) {
                    if let Some(arr) = v.as_array() {
                        for m in arr {
                            if m["focused"].as_bool().unwrap_or(false) {
                                let h = m["height"].as_f64().unwrap_or(1080.0);
                                let scale = m["scale"].as_f64().unwrap_or(1.0);
                                return (h / scale).floor() as i32;
                            }
                        }
                        if let Some(first) = arr.first() {
                            let h = first["height"].as_f64().unwrap_or(1080.0);
                            let scale = first["scale"].as_f64().unwrap_or(1.0);
                            return (h / scale).floor() as i32;
                        }
                    }
                }
            }
        }
    }
    1080
}

fn get_position_mode() -> &'static str {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/jocky".to_string());
    let cfg_path = PathBuf::from(home).join(".config/waybar/config");
    if let Ok(content) = fs::read_to_string(&cfg_path) {
        if content.contains("\"position\": \"top\"")
            || content.contains("\"position\":  \"top\"")
            || content.contains("\"position\":\"top\"")
        {
            return "top";
        }
    }
    "bottom"
}

fn get_start_hidden() -> bool {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/jocky".to_string());
    let cfg_path = PathBuf::from(home).join(".config/waybar/config");
    if let Ok(content) = fs::read_to_string(&cfg_path) {
        return content.contains("\"start_hidden\": true")
            || content.contains("\"start_hidden\":true");
    }
    true
}

fn find_waybar_pid() -> Option<i32> {
    let output = Command::new("pgrep").args(["-x", "waybar"]).output().ok()?;
    let s = String::from_utf8_lossy(&output.stdout);
    for line in s.lines() {
        if let Ok(pid) = line.trim().parse::<i32>() {
            return Some(pid);
        }
    }
    None
}

fn main() {
    unsafe {
        libc::signal(libc::SIGINT, handle_term as *const () as usize);
        libc::signal(libc::SIGTERM, handle_term as *const () as usize);
        libc::signal(libc::SIGUSR2, handle_usr2 as *const () as usize);
        libc::signal(libc::SIGCHLD, libc::SIG_IGN); // Automatically reap exited child processes to prevent zombies
    }

    let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let pid_file = PathBuf::from(&runtime_dir).join("waybar-autohide.pid");
    let pinned_file = PathBuf::from(&runtime_dir).join("waybar-pinned");

    let my_pid = std::process::id();
    let _ = fs::write(&pid_file, format!("{}\n", my_pid));

    struct PidGuard(PathBuf);
    impl Drop for PidGuard {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.0);
        }
    }
    let _guard = PidGuard(pid_file.clone());

    // Kill existing waybar and relaunch cleanly
    let _ = Command::new("pkill").args(["-x", "waybar"]).status();
    thread::sleep(Duration::from_millis(250));

    let _ = Command::new("waybar").spawn();
    thread::sleep(Duration::from_millis(300));

    let mut last_waybar_pid = find_waybar_pid();
    for _ in 0..10 {
        if last_waybar_pid.is_some() {
            break;
        }
        thread::sleep(Duration::from_millis(100));
        last_waybar_pid = find_waybar_pid();
    }

    let mut visible = !get_start_hidden();
    let mut pos_mode = get_position_mode();

    let socket_path = match get_hyprland_socket_path() {
        Some(p) => p,
        None => {
            eprintln!("ERROR: Could not find Hyprland IPC socket");
            return;
        }
    };

    let mut screen_h = get_screen_height(&socket_path);
    let reveal_margin = 20;
    let hide_margin = 80;

    let poll_interval = Duration::from_millis(40);

    while RUNNING.load(Ordering::SeqCst) {
        if FORCED_CHECK.swap(false, Ordering::SeqCst) {
            pos_mode = get_position_mode();
            screen_h = get_screen_height(&socket_path);
        } else {
            thread::sleep(poll_interval);
        }

        // Check if waybar is still running
        let wb_pid = match last_waybar_pid {
            Some(pid) => {
                let alive = unsafe { libc::kill(pid, 0) == 0 };
                if alive {
                    pid
                } else {
                    match find_waybar_pid() {
                        Some(new_pid) => {
                            last_waybar_pid = Some(new_pid);
                            visible = !get_start_hidden();
                            pos_mode = get_position_mode();
                            new_pid
                        }
                        None => continue,
                    }
                }
            }
            None => match find_waybar_pid() {
                Some(new_pid) => {
                    last_waybar_pid = Some(new_pid);
                    visible = !get_start_hidden();
                    new_pid
                }
                None => continue,
            },
        };

        // If pinned, ensure waybar is visible
        if pinned_file.exists() {
            if !visible {
                unsafe {
                    libc::kill(wb_pid, libc::SIGUSR1);
                }
                visible = true;
            }
            continue;
        }

        // Query cursor position directly from Hyprland IPC socket
        if let Some((_x, y)) = get_cursor_pos(&socket_path) {
            if pos_mode == "top" {
                if !visible && y <= reveal_margin {
                    unsafe {
                        libc::kill(wb_pid, libc::SIGUSR1);
                    }
                    visible = true;
                } else if visible && y >= hide_margin {
                    if !pinned_file.exists() {
                        unsafe {
                            libc::kill(wb_pid, libc::SIGUSR1);
                        }
                        visible = false;
                    }
                }
            } else {
                let reveal_at = screen_h - reveal_margin;
                let hide_at = screen_h - hide_margin;

                if !visible && y >= reveal_at {
                    unsafe {
                        libc::kill(wb_pid, libc::SIGUSR1);
                    }
                    visible = true;
                } else if visible && y <= hide_at {
                    if !pinned_file.exists() {
                        unsafe {
                            libc::kill(wb_pid, libc::SIGUSR1);
                        }
                        visible = false;
                    }
                }
            }
        }
    }
}
