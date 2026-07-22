use serde::{Deserialize, Serialize};
use std::process::{Child, Command};
use std::sync::Mutex;
use sysinfo::System;
use tauri::State;

/// Represents the lifecycle state of a sidecar service.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ServiceStatus {
    Stopped,
    Starting,
    Running,
    Error,
}

/// A managed sidecar process (Handy CLI, Voicebox, or agent-meow).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceInfo {
    pub id: String,
    pub name: String,
    pub description: String,
    pub url: Option<String>,
    pub status: ServiceStatus,
    pub pid: Option<u32>,
    pub port: Option<u16>,
}

/// Holds the running child processes so we can kill them on quit.
struct SidecarState {
    children: Vec<Child>,
}

impl Drop for SidecarState {
    fn drop(&mut self) {
        for child in &mut self.children {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// Resolve the sidecar binary path from the bundled resources directory.
/// In dev mode, falls back to system PATH.
fn resolve_sidecar(exe_name: &str) -> Option<String> {
    // In a bundled Tauri app, resources are in the app's resource directory.
    // We check a few candidate locations.
    if let Ok(resource_dir) = std::env::current_exe() {
        let parent = resource_dir.parent()?;
        let candidates = [
            parent.join("sidecars").join(exe_name),
            parent.join("resources").join("sidecars").join(exe_name),
            parent.join(exe_name),
        ];
        for candidate in &candidates {
            if candidate.exists() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }
    }
    // Dev fallback: check PATH
    if let Ok(path) = which::which(exe_name) {
        return Some(path.to_string_lossy().to_string());
    }
    None
}

/// Check if a port is listening (used for health checks).
fn is_port_open(port: u16) -> bool {
    use std::net::TcpStream;
    use std::time::Duration;
    let addr = format!("127.0.0.1:{}", port);
    TcpStream::connect_timeout(
        &addr.parse().unwrap_or("127.0.0.1:0".parse().unwrap()),
        Duration::from_millis(500),
    )
    .is_ok()
}

/// Check if a process is running by PID.
fn is_pid_alive(pid: u32) -> bool {
    let mut sys = System::new();
    sys.refresh_processes();
    sys.process(sysinfo::Pid::from(pid as usize)).is_some()
}

/// Get current service statuses by checking ports and PIDs.
#[tauri::command]
fn get_service_statuses(state: State<Mutex<Vec<ServiceInfo>>>) -> Vec<ServiceInfo> {
    let mut services = state.lock().unwrap();
    for svc in services.iter_mut() {
        if let Some(port) = svc.port {
            if is_port_open(port) {
                svc.status = ServiceStatus::Running;
            } else if let Some(pid) = svc.pid {
                if is_pid_alive(pid) {
                    svc.status = ServiceStatus::Running;
                } else {
                    svc.status = ServiceStatus::Stopped;
                    svc.pid = None;
                }
            } else {
                svc.status = ServiceStatus::Stopped;
            }
        } else if let Some(pid) = svc.pid {
            if is_pid_alive(pid) {
                svc.status = ServiceStatus::Running;
            } else {
                svc.status = ServiceStatus::Stopped;
                svc.pid = None;
            }
        } else {
            svc.status = ServiceStatus::Stopped;
        }
    }
    services.clone()
}

/// Start a specific sidecar service by ID.
#[tauri::command]
fn start_service(
    id: String,
    state: State<Mutex<Vec<ServiceInfo>>>,
    sidecar_state: State<Mutex<SidecarState>>,
) -> Result<ServiceInfo, String> {
    let mut services = state.lock().unwrap();

    let svc = services
        .iter_mut()
        .find(|s| s.id == id)
        .ok_or_else(|| format!("Service '{}' not found", id))?;

    if svc.status == ServiceStatus::Running {
        return Ok(svc.clone());
    }

    svc.status = ServiceStatus::Starting;

    // Determine the executable name and arguments
    let (exe_name, args): (&str, Vec<&str>) = match svc.id.as_str() {
        "handy" => ("handy", vec![]),
        "voicebox" => ("voicebox", vec![]),
        "agent-meow" => ("agent-meow", vec![]),
        _ => return Err(format!("Unknown service: {}", id)),
    };

    let exe_path = resolve_sidecar(exe_name)
        .ok_or_else(|| format!("{} binary not found. Make sure sidecars are bundled.", exe_name))?;

    let child = Command::new(&exe_path)
        .args(&args)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start {}: {}", svc.name, e))?;

    svc.pid = Some(child.id());
    svc.status = ServiceStatus::Running;

    // Store child for cleanup
    let mut sc = sidecar_state.lock().unwrap();
    sc.children.push(child);

    log::info!("Started {} (PID: {})", svc.name, svc.pid.unwrap());
    Ok(svc.clone())
}

/// Start all sidecar services.
#[tauri::command]
fn start_all_services(
    state: State<Mutex<Vec<ServiceInfo>>>,
    sidecar_state: State<Mutex<SidecarState>>,
) -> Vec<ServiceInfo> {
    let ids: Vec<String> = state
        .lock()
        .unwrap()
        .iter()
        .map(|s| s.id.clone())
        .collect();

    for id in ids {
        let _ = start_service(id, state.clone(), sidecar_state.clone());
    }

    get_service_statuses(state)
}

/// Stop a specific sidecar service.
#[tauri::command]
fn stop_service(
    id: String,
    state: State<Mutex<Vec<ServiceInfo>>>,
) -> Result<ServiceInfo, String> {
    let mut services = state.lock().unwrap();

    let svc = services
        .iter_mut()
        .find(|s| s.id == id)
        .ok_or_else(|| format!("Service '{}' not found", id))?;

    if let Some(pid) = svc.pid {
        // Kill the process tree
        if cfg!(windows) {
            let _ = Command::new("taskkill")
                .args(["/PID", &pid.to_string(), "/T", "/F"])
                .output();
        } else {
            let _ = Command::new("kill")
                .args(["-9", &pid.to_string()])
                .output();
        }
        svc.pid = None;
    }

    svc.status = ServiceStatus::Stopped;
    log::info!("Stopped {}", svc.name);
    Ok(svc.clone())
}

/// Stop all sidecar services (called on app quit).
#[tauri::command]
fn stop_all_services(state: State<Mutex<Vec<ServiceInfo>>>) -> Vec<ServiceInfo> {
    let ids: Vec<String> = state
        .lock()
        .unwrap()
        .iter()
        .map(|s| s.id.clone())
        .collect();

    for id in ids {
        let _ = stop_service(id, state.clone());
    }

    get_service_statuses(state)
}

/// Open the agent-meow web UI in the default browser.
#[tauri::command]
fn open_agent_meow_ui() -> Result<(), String> {
    let url = "http://127.0.0.1:8000";
    if cfg!(windows) {
        Command::new("rundll32")
            .args(["url.dll,FileProtocolHandler", url])
            .spawn()
            .map_err(|e| e.to_string())?;
    } else if cfg!(target_os = "macos") {
        Command::new("open").arg(url).spawn().map_err(|e| e.to_string())?;
    } else {
        Command::new("xdg-open").arg(url).spawn().map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Initialize the service definitions.
fn default_services() -> Vec<ServiceInfo> {
    vec![
        ServiceInfo {
            id: "handy".to_string(),
            name: "Handy".to_string(),
            description: "Speech-to-Text (Whisper/Parakeet)".to_string(),
            url: None,
            status: ServiceStatus::Stopped,
            pid: None,
            port: None,
        },
        ServiceInfo {
            id: "voicebox".to_string(),
            name: "Voicebox".to_string(),
            description: "Text-to-Speech (7 engines, voice cloning)".to_string(),
            url: Some("http://127.0.0.1:17493".to_string()),
            status: ServiceStatus::Stopped,
            pid: None,
            port: Some(17493),
        },
        ServiceInfo {
            id: "agent-meow".to_string(),
            name: "agent-meow".to_string(),
            description: "Agent execution server + web UI".to_string(),
            url: Some("http://127.0.0.1:8000".to_string()),
            status: ServiceStatus::Stopped,
            pid: None,
            port: Some(8000),
        },
    ]
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    env_logger::init();

    let services = default_services();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Mutex::new(services))
        .manage(Mutex::new(SidecarState {
            children: Vec::new(),
        }))
        .invoke_handler(tauri::generate_handler![
            get_service_statuses,
            start_service,
            start_all_services,
            stop_service,
            stop_all_services,
            open_agent_meow_ui,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                // Stop all services when the window is closed
                let state = window.state::<Mutex<Vec<ServiceInfo>>>();
                let ids: Vec<String> = state
                    .lock()
                    .unwrap()
                    .iter()
                    .map(|s| s.id.clone())
                    .collect();
                for id in ids {
                    let _ = stop_service(id, window.state());
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Voice Stack");
}