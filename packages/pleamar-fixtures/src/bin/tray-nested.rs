//! A tray item with a nested menu, for checking that the bar's menu walks
//! submenus.
//!
//! Port of `files/pleamar/scripts/fixtures/tray-nested.py`: a real
//! `org.kde.StatusNotifierItem` whose `com.canonical.dbusmenu` has a parent
//! with children, a separator inside it, a checkable leaf and one plain
//! action. Every activation is printed as `event <id> <event-id>`.
//!
//!     tray-nested            # serves until killed
//!     tray-nested --once     # exits after the first click

use std::collections::HashMap;
use std::process::ExitCode;
use zbus::blocking::{Connection, Proxy};
use zbus::interface;
use zbus::zvariant::{ObjectPath, StructureBuilder, Value};

const ITEM_NAME: &str = "org.kde.StatusNotifierItem-stub";
const ITEM_PATH: &str = "/StatusNotifierItem";
const MENU_PATH: &str = "/MenuBar";
const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";

/// `(id, properties, children)` — the dbusmenu node of the wire signature
/// `(ia{sv}av)`. Children are variants of this same structure.
#[derive(serde::Serialize, zbus::zvariant::Type)]
struct MenuNode(i32, HashMap<String, Value<'static>>, Vec<Value<'static>>);

impl From<MenuNode> for Value<'static> {
    fn from(node: MenuNode) -> Self {
        let structure = StructureBuilder::new()
            .add_field(node.0)
            .add_field(node.1)
            .add_field(node.2)
            .build();
        Value::new(structure)
    }
}

fn props(
    label: &str,
    kind: Option<&str>,
    toggle_type: Option<&str>,
    toggle_state: Option<i32>,
) -> HashMap<String, Value<'static>> {
    let mut out = HashMap::new();
    out.insert("label".to_string(), Value::from(label.to_string()));
    if let Some(kind) = kind {
        out.insert("type".to_string(), Value::from(kind.to_string()));
    }
    if let Some(toggle_type) = toggle_type {
        out.insert("toggle-type".to_string(), Value::from(toggle_type.to_string()));
    }
    if let Some(toggle_state) = toggle_state {
        out.insert("toggle-state".to_string(), Value::from(toggle_state));
    }
    out.insert("enabled".to_string(), Value::from(true));
    out.insert("visible".to_string(), Value::from(true));
    out
}

/// The menu: 1 is a parent whose children are reachable only through it. 0 is
/// the root, which is never drawn (the engine takes its children).
fn node(id: i32) -> MenuNode {
    let (props, children): (HashMap<String, Value<'static>>, Vec<i32>) = match id {
        0 => (props("", None, None, None), vec![1, 2, 3]),
        1 => (props("Nested parent", None, None, None), vec![11, 12, 13, 14]),
        2 => (props("", Some("separator"), None, None), Vec::new()),
        3 => (props("Plain action", None, None, None), Vec::new()),
        11 => (props("Leaf one", None, None, None), Vec::new()),
        12 => (props("Leaf two", None, None, None), Vec::new()),
        13 => (props("", Some("separator"), None, None), Vec::new()),
        14 => (
            props("Leaf checked", None, Some("checkmark"), Some(1)),
            Vec::new(),
        ),
        _ => (props("", None, None, None), Vec::new()),
    };
    MenuNode(
        id,
        props,
        children.into_iter().map(|child| node(child).into()).collect(),
    )
}

struct Item {
    once: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

#[interface(name = "org.kde.StatusNotifierItem")]
impl Item {
    fn context_menu(&self, x: i32, y: i32) {
        let _ = (x, y);
    }

    fn activate(&self, x: i32, y: i32) {
        let _ = (x, y);
        println!("event 0 activated");
    }

    fn secondary_activate(&self, x: i32, y: i32) {
        let _ = (x, y);
    }

    fn scroll(&self, delta: i32, orientation: String) {
        let _ = (delta, orientation);
    }

    #[zbus(property)]
    fn category(&self) -> String {
        "ApplicationStatus".to_string()
    }

    #[zbus(property)]
    fn id(&self) -> String {
        "stub-nested".to_string()
    }

    #[zbus(property)]
    fn title(&self) -> String {
        "Nested tray stub".to_string()
    }

    #[zbus(property)]
    fn status(&self) -> String {
        "Active".to_string()
    }

    #[zbus(property)]
    fn window_id(&self) -> i32 {
        0
    }

    #[zbus(property)]
    fn icon_name(&self) -> String {
        "applications-system".to_string()
    }

    #[zbus(property)]
    fn icon_pixmap(&self) -> Vec<(i32, i32, Vec<u8>)> {
        Vec::new()
    }

    #[zbus(property)]
    fn icon_theme_path(&self) -> String {
        String::new()
    }

    #[zbus(property)]
    fn overlay_icon_name(&self) -> String {
        String::new()
    }

    #[zbus(property)]
    fn attention_icon_name(&self) -> String {
        String::new()
    }

    #[zbus(property)]
    fn tool_tip(&self) -> (String, Vec<(i32, i32, Vec<u8>)>, String, String) {
        let _ = &self.once;
        (
            String::new(),
            Vec::new(),
            "Nested tray stub".to_string(),
            "a parent and its children".to_string(),
        )
    }

    #[zbus(property)]
    fn item_is_menu(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn menu(&self) -> ObjectPath<'static> {
        ObjectPath::from_static_str_unchecked(MENU_PATH)
    }
}

struct Menu {
    once: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

#[interface(name = "com.canonical.dbusmenu")]
impl Menu {
    fn get_layout(&self, parent_id: i32, depth: i32, names: Vec<String>) -> (u32, MenuNode) {
        let _ = (depth, names);
        (1, node(parent_id))
    }

    fn get_group_properties(
        &self,
        ids: Vec<i32>,
        names: Vec<String>,
    ) -> Vec<(i32, HashMap<String, Value<'static>>)> {
        let _ = names;
        ids.into_iter()
            .map(|id| {
                let full = node(id);
                (id, full.1)
            })
            .collect()
    }

    fn about_to_show(&self, item_id: i32) -> bool {
        let _ = item_id;
        false
    }

    fn event(&self, item_id: i32, event_id: String, data: Value<'_>, timestamp: u32) {
        let _ = (data, timestamp);
        println!("event {item_id} {event_id}");
        if self.once.load(std::sync::atomic::Ordering::Relaxed)
            && (event_id == "clicked" || event_id == "activated")
        {
            std::process::exit(0);
        }
    }

    #[zbus(signal)]
    async fn items_properties_updated(
        context: &zbus::SignalContext<'_>,
        updated: Vec<(i32, HashMap<String, Value<'static>>)>,
        removed: Vec<(i32, Vec<String>)>,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn layout_updated(
        context: &zbus::SignalContext<'_>,
        revision: u32,
        parent: i32,
    ) -> zbus::Result<()>;

    #[zbus(property)]
    fn version(&self) -> u32 {
        1
    }

    #[zbus(property)]
    fn text_direction(&self) -> String {
        "ltr".to_string()
    }

    #[zbus(property)]
    fn status(&self) -> String {
        "normal".to_string()
    }

    #[zbus(property)]
    fn icon_theme_path(&self) -> Vec<String> {
        Vec::new()
    }
}

fn main() -> ExitCode {
    let mut once = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "-h" | "--help" => {
                println!("usage: tray-nested [-h] [--once]");
                return ExitCode::SUCCESS;
            }
            "--once" => once = true,
            other => {
                eprintln!("usage: tray-nested [-h] [--once]");
                eprintln!("tray-nested: error: unrecognized arguments: {other}");
                return ExitCode::from(2);
            }
        }
    }

    let connection = match Connection::session() {
        Ok(connection) => connection,
        Err(error) => {
            eprintln!("tray-nested: cannot connect to the session bus: {error}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(error) = connection.request_name(ITEM_NAME) {
        eprintln!("tray-nested: cannot own {ITEM_NAME}: {error}");
        return ExitCode::FAILURE;
    }
    let once = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(once));
    let object_server = connection.object_server();
    for path in [ITEM_PATH, MENU_PATH] {
        if let Err(error) = object_server.at(path, Item { once: once.clone() }) {
            eprintln!("tray-nested: cannot export the item on {path}: {error}");
            return ExitCode::FAILURE;
        }
        if let Err(error) = object_server.at(path, Menu { once: once.clone() }) {
            eprintln!("tray-nested: cannot export the menu on {path}: {error}");
            return ExitCode::FAILURE;
        }
    }

    let watcher = match Proxy::new(
        &connection,
        WATCHER,
        WATCHER_PATH,
        "org.kde.StatusNotifierWatcher",
    ) {
        Ok(watcher) => watcher,
        Err(error) => {
            eprintln!("tray-nested: no {WATCHER} on the bus: {error}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(error) = watcher.call_method("RegisterStatusNotifierItem", &(ITEM_NAME,)) {
        eprintln!("tray-nested: cannot register with {WATCHER}: {error}");
        return ExitCode::FAILURE;
    }

    println!("serving {ITEM_NAME}{ITEM_PATH} · menu {MENU_PATH} · parent 1 has 4 children");
    std::thread::park();
    ExitCode::SUCCESS
}
