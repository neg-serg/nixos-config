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

#[cfg(test)]
mod tests {
    use super::*;

    // Reference output captured from the shipped `kbd.sh` (fake hyprctl) so
    // both implementations pin the same bytes.
    const REFERENCE_DEVICES: &str = r#"{"keyboards":[
        {"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"},
        {"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0,"active_keymap":"German"},
        {"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":0,"active_keymap":"French"}
    ]}"#;

    fn rendered(json: &str, submap: &str, caps: bool) -> String {
        let devices: Value = serde_json::from_str(json).expect("fixture");
        render_data(&devices, submap, caps)
    }

    #[test]
    fn main_keyboard_wins_and_key_order_is_the_shell_order() {
        assert_eq!(
            rendered(REFERENCE_DEVICES, "", false),
            concat!(
                r#"{"device":"kbd-main","main":true,"index":1,"keymap":"Russian","code":"ru","#,
                r#""layouts":["us","ru"],"submap":"","caps":false,"#,
                r#""keyboards":[{"name":"kbd-main","main":true},"#,
                r#"{"name":"virtual-keyboard","main":false},{"name":"kbd-2","main":false}]}"#
            )
        );
    }

    #[test]
    fn non_virtual_keyboard_with_layout_is_the_fallback() {
        let json = r#"{"keyboards":[
            {"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0},
            {"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":1,"active_keymap":"German"}
        ]}"#;
        assert_eq!(
            rendered(json, "", false),
            concat!(
                r#"{"device":"kbd-2","main":false,"index":1,"keymap":"German","code":"de","#,
                r#""layouts":["fr","de"],"submap":"","caps":false,"#,
                r#""keyboards":[{"name":"virtual-keyboard","main":false},{"name":"kbd-2","main":false}]}"#
            )
        );
    }

    #[test]
    fn virtual_keyboards_are_skipped_unless_nothing_else_exists() {
        let only_virtual = r#"{"keyboards":[
            {"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0}
        ]}"#;
        assert_eq!(
            rendered(only_virtual, "", false),
            concat!(
                r#"{"device":"virtual-keyboard","main":false,"index":0,"keymap":"","code":"de","#,
                r#""layouts":["de"],"submap":"","caps":false,"#,
                r#""keyboards":[{"name":"virtual-keyboard","main":false}]}"#
            )
        );
    }

    #[test]
    fn no_keyboards_is_an_empty_default() {
        assert_eq!(
            rendered("{}", "", false),
            concat!(
                r#"{"device":"","main":false,"index":0,"keymap":"","code":"","layouts":[],"#,
                r#""submap":"","caps":false,"keyboards":[]}"#
            )
        );
        assert_eq!(
            rendered(r#"{"keyboards":[]}"#, "", false),
            concat!(
                r#"{"device":"","main":false,"index":0,"keymap":"","code":"","layouts":[],"#,
                r#""submap":"","caps":false,"keyboards":[]}"#
            )
        );
    }

    #[test]
    fn submap_and_caps_are_carried_through() {
        let devices: Value = serde_json::from_str(REFERENCE_DEVICES).expect("fixture");
        let data = render_data(&devices, "resize", true);
        assert!(data.contains(r#""submap":"resize","caps":true"#));
    }

    #[test]
    fn layout_split_drops_empty_parts() {
        let data = rendered(
            r#"{"keyboards":[{"name":"k","main":true,"layout":",us,,ru,","active_layout_index":0}]}"#,
            "",
            false,
        );
        assert!(data.contains(r#""layouts":["us","ru"]"#));
        assert!(data.contains(r#""code":"us""#));
    }

    #[test]
    fn out_of_range_index_has_no_code() {
        let data = rendered(
            r#"{"keyboards":[{"name":"k","main":true,"layout":"us","active_layout_index":7}]}"#,
            "",
            false,
        );
        assert!(data.contains(r#""index":7"#));
        assert!(data.contains(r#""code":"""#));
    }

    #[test]
    fn negative_index_counts_from_the_end() {
        let data = rendered(
            r#"{"keyboards":[{"name":"k","main":true,"layout":"us,ru","active_layout_index":-1}]}"#,
            "",
            false,
        );
        assert!(data.contains(r#""index":-1"#));
        assert!(data.contains(r#""code":"ru""#));
    }

    #[test]
    fn strings_are_json_escaped() {
        let data = rendered(
            r#"{"keyboards":[{"name":"k\"b\\d","main":true,"layout":"us"}]}"#,
            "a\"b",
            false,
        );
        assert!(data.contains(r#""device":"k\"b\\d""#));
        assert!(data.contains(r#""submap":"a\"b""#));
    }

    #[test]
    fn empty_layout_string_does_not_qualify_but_is_still_reported() {
        let data = rendered(
            r#"{"keyboards":[{"name":"k","main":false,"layout":"","active_layout_index":0}]}"#,
            "",
            false,
        );
        assert!(data.contains(r#""device":"k""#));
        assert!(data.contains(r#""layouts":[]"#));
        assert!(data.contains(r#""code":"""#));
    }
}
