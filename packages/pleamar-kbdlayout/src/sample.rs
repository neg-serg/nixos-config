//! The `layout` sample: the selection rules and the compact JSON object.
//!
//! This is the `jq` program in `build_status()` of `kbd.sh`, translated one
//! expression at a time. The output is a compact JSON object with the shell's
//! key order (`device`, `main`, `index`, `keymap`, `code`, `layouts`, `submap`,
//! `caps`, `keyboards`), because byte-compatible sample lines are part of the
//! helper-worker contract.

use serde_json::Value;

/// JSON-encode a string the way `jq --arg`/`tojson` does for the shapes the
/// compositor reports (quotes, backslashes and control characters escaped,
/// UTF-8 left as is).
pub fn quote(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| String::from("\"\""))
}

fn text(value: &Value, key: &str) -> String {
    match value.get(key) {
        Some(Value::String(text)) => text.clone(),
        // `(.field // "")`: null/missing become "", everything else survives
        // in jq. Keyboard descriptions are strings in practice; non-strings
        // are treated as the empty default rather than mis-typed output.
        Some(Value::Bool(true)) => String::from("true"),
        Some(Value::Number(number)) => number.to_string(),
        _ => String::new(),
    }
}

fn is_main(value: &Value) -> bool {
    matches!(value.get("main"), Some(Value::Bool(true)))
}

fn keyboard_values(devices: &Value) -> Vec<&Value> {
    match devices.get("keyboards") {
        Some(Value::Array(items)) => items.iter().collect(),
        _ => Vec::new(),
    }
}

fn bool_text(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

/// `$layouts[($sel.active_layout_index // 0)]`, with jq's negative-index rule.
fn layout_code(layouts: &[String], index: &Value) -> String {
    let position = match index.as_i64() {
        Some(number) => number,
        None => match index.as_u64().and_then(|number| i64::try_from(number).ok()) {
            Some(number) => number,
            None => return String::new(),
        },
    };
    let position = if position < 0 {
        position + layouts.len() as i64
    } else {
        position
    };
    if position < 0 {
        return String::new();
    }
    layouts.get(position as usize).cloned().unwrap_or_default()
}

/// Render the `data` object for one `layout` sample.
///
/// `devices` is the parsed `hyprctl -j devices` document, `submap` the cleaned
/// `hyprctl submap` answer and `caps` the LED state.
pub fn render_data(devices: &Value, submap: &str, caps: bool) -> String {
    let keyboards = keyboard_values(devices);

    // The shell selected, in order: a main keyboard, then any non-virtual
    // keyboard with a layout, then the first keyboard of any kind.
    let mut selected: Option<&Value> = None;
    for keyboard in &keyboards {
        if is_main(keyboard) {
            selected = Some(keyboard);
            break;
        }
    }
    if selected.is_none() {
        for keyboard in &keyboards {
            let name = text(keyboard, "name").to_ascii_lowercase();
            let layout = text(keyboard, "layout");
            if !name.contains("virtual") && !layout.is_empty() {
                selected = Some(keyboard);
                break;
            }
        }
    }
    if selected.is_none() {
        selected = keyboards.first().copied();
    }

    // Empty `$k` means `$sel` is `{}` and every field falls back to its default.
    let empty = Value::Object(serde_json::Map::new());
    let selected = selected.unwrap_or(&empty);

    let device = text(selected, "name");
    let main = is_main(selected);
    let index = match selected.get("active_layout_index") {
        Some(Value::Number(number)) => Value::Number(number.clone()),
        // `($sel.active_layout_index // 0)`: null and false become zero.
        _ => Value::from(0),
    };
    let keymap = text(selected, "active_keymap");
    let layouts: Vec<String> = text(selected, "layout")
        .split(',')
        .filter(|part| !part.is_empty())
        .map(str::to_string)
        .collect();
    let code = layout_code(&layouts, &index);

    let mut output = String::with_capacity(256);
    output.push_str("{\"device\":");
    output.push_str(&quote(&device));
    output.push_str(",\"main\":");
    output.push_str(bool_text(main));
    output.push_str(",\"index\":");
    output.push_str(&index.to_string());
    output.push_str(",\"keymap\":");
    output.push_str(&quote(&keymap));
    output.push_str(",\"code\":");
    output.push_str(&quote(&code));
    output.push_str(",\"layouts\":[");
    for (position, layout) in layouts.iter().enumerate() {
        if position > 0 {
            output.push(',');
        }
        output.push_str(&quote(layout));
    }
    output.push_str("],\"submap\":");
    output.push_str(&quote(submap));
    output.push_str(",\"caps\":");
    output.push_str(bool_text(caps));
    output.push_str(",\"keyboards\":[");
    for (position, keyboard) in keyboards.iter().enumerate() {
        if position > 0 {
            output.push(',');
        }
        output.push_str("{\"name\":");
        output.push_str(&quote(&text(keyboard, "name")));
        output.push_str(",\"main\":");
        output.push_str(bool_text(is_main(keyboard)));
        output.push('}');
    }
    output.push_str("]}");
    output
}
