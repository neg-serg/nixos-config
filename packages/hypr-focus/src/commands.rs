use hyprland::dispatch::{
    Dispatch, DispatchType, FullscreenType, SwapWithMasterParam, WindowIdentifier,
    WorkspaceIdentifierWithSpecial,
};
use hyprland::keyword::Keyword;
use hyprland::shared::Address;
use std::env;
use std::fs;
use std::process::exit;

pub fn daemon() {
    crate::daemon::run().unwrap_or_else(|e| {
        eprintln!("Daemon error: {}", e);
        exit(1);
    });
}

pub fn switch_window() {
    let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| {
        eprintln!("$XDG_RUNTIME_DIR not set");
        exit(1);
    });
    let instance = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_else(|_| {
        eprintln!("$HYPRLAND_INSTANCE_SIGNATURE not set");
        exit(1);
    });
    let path = format!("{}/hypr/{}/focus-history", runtime_dir, instance);
    let addr = fs::read_to_string(&path).unwrap_or_default().trim().to_string();
    if addr.is_empty() {
        eprintln!("No focus history yet");
        exit(1);
    }
    Dispatch::call(DispatchType::FocusWindow(WindowIdentifier::Address(
        Address::new(&addr),
    )))
    .unwrap_or_else(|e| {
        eprintln!("Focus failed: {}", e);
        exit(1);
    });
}

pub fn workspace(target: &str) {
    Dispatch::call(DispatchType::Workspace(
        WorkspaceIdentifierWithSpecial::Name(target),
    ))
    .unwrap_or_else(|e| {
        eprintln!("Workspace failed: {}", e);
        exit(1);
    });
}

pub fn move_to_workspace(target: &str, follow: bool) {
    Dispatch::call(DispatchType::Custom("movetoworkspacesilent", target))
        .unwrap_or_else(|e| {
            eprintln!("Move failed: {}", e);
            exit(1);
        });
    if follow {
        Dispatch::call(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Name(
            target,
        )))
        .unwrap_or_else(|e| {
            eprintln!("Follow failed: {}", e);
            exit(1);
        });
    }
}

pub fn float() {
    Dispatch::call(DispatchType::ToggleFloating(None)).unwrap_or_else(|e| {
        eprintln!("Float failed: {}", e);
        exit(1);
    });
}

pub fn fullscreen() {
    Dispatch::call(DispatchType::ToggleFullscreen(FullscreenType::Maximize))
        .unwrap_or_else(|e| {
            eprintln!("Fullscreen failed: {}", e);
            exit(1);
        });
}

pub fn pin() {
    Dispatch::call(DispatchType::TogglePin).unwrap_or_else(|e| {
        eprintln!("Pin failed: {}", e);
        exit(1);
    });
}

pub fn layout(name: Option<&str>) {
    if let Some(layout_name) = name {
        Keyword::set("general:layout", layout_name).unwrap_or_else(|e| {
            eprintln!("Layout failed: {}", e);
            exit(1);
        });
    } else {
        let current = Keyword::get("general:layout")
            .map(|k| k.value.to_string())
            .unwrap_or_else(|_| "master".to_string());
        let next = if current.trim() == "master" {
            "dwindle"
        } else {
            "master"
        };
        Keyword::set("general:layout", next).unwrap_or_else(|e| {
            eprintln!("Layout toggle failed: {}", e);
            exit(1);
        });
    }
}

pub fn orientation() {
    Dispatch::call(DispatchType::OrientationNext).unwrap_or_else(|e| {
        eprintln!("Orientation failed: {}", e);
        exit(1);
    });
}

pub fn split_ratio(value: &str) {
    if value.starts_with('+') || value.starts_with('-') {
        Dispatch::call(DispatchType::Custom("splitratio", value)).unwrap_or_else(|e| {
            eprintln!("Split ratio failed: {}", e);
            exit(1);
        });
    } else {
        Keyword::set("master:mfact", value).unwrap_or_else(|e| {
            eprintln!("Split ratio failed: {}", e);
            exit(1);
        });
    }
}

pub fn swap_master() {
    Dispatch::call(DispatchType::SwapWithMaster(SwapWithMasterParam::Auto))
        .unwrap_or_else(|e| {
            eprintln!("Swap master failed: {}", e);
            exit(1);
        });
}

pub fn add_master() {
    Dispatch::call(DispatchType::AddMaster).unwrap_or_else(|e| {
        eprintln!("Add master failed: {}", e);
        exit(1);
    });
}

pub fn remove_master() {
    Dispatch::call(DispatchType::RemoveMaster).unwrap_or_else(|e| {
        eprintln!("Remove master failed: {}", e);
        exit(1);
    });
}

pub fn toggle_split() {
    Dispatch::call(DispatchType::ToggleSplit).unwrap_or_else(|e| {
        eprintln!("Toggle split failed: {}", e);
        exit(1);
    });
}

pub fn preselect(direction: &str) {
    Dispatch::call(DispatchType::Custom(
        "layoutmsg",
        &format!("preselect {}", direction),
    ))
    .unwrap_or_else(|e| {
        eprintln!("Preselect failed: {}", e);
        exit(1);
    });
}
