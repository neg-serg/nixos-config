//! Rewrite the owned blocks of the terminal profile's `cordis.patch.yml`.
//!
//! Port of `modules/user/nix-maid/apps/dsh-tui-preset-patch.py`. Three facts
//! about the dsh-TUI bundle and the 0.2.0 preset registry the profile layer
//! mirrors:
//!   * its bundle patch replaces the base `agent-presets` roster row with the
//!     scoped `dsh-tui-agent-presets` id (legacy, disabled since 0.1.7), while
//!     the registry row wired for the current harness generation is
//!     `dsh-tui-agent-preset-registry` - the fallback preset is therefore named
//!     in that row's `config.default`;
//!   * the bundle ships no presets of its own, so this deployment declares
//!     `neg` and `fast` itself (see dsh-presets.nix);
//!   * the bundle already inserts its own code-runtime row, so a second one is
//!     a duplicate `codeRuntime` registration that kills the boot - the runtime
//!     block is retired and any leftover copy is consumed (OWNED_MARKERS).
//!
//! Usage: dsh-patch tui-preset <patch.yml> <rows-file> <presets-json> [prefix]

use serde_json::Value;

pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        eprintln!("usage: dsh-patch tui-preset <patch.yml> <rows> <presets.json> [prefix]");
        return 2;
    }
    let path = args[0].as_str();
    let rows_path = args.get(1);
    let presets_path = args.get(2);
    let prefix = args.get(3).map(String::as_str).unwrap_or("dsh-tui-ensure");

    let marker_presets = format!("# {prefix}: agent presets");
    let marker_preset = format!("# {prefix}: default preset");
    let marker_runtime = format!("# {prefix}: code runtime");
    let marker_plugins = format!("# {prefix}: plugin rows");
    let marker_legacy = format!("# {prefix}: retired TUI rows");
    let owned_markers = [
        marker_presets.as_str(),
        marker_preset.as_str(),
        marker_runtime.as_str(),
        marker_plugins.as_str(),
        marker_legacy.as_str(),
    ];

    let mut plugin_rows: Vec<String> = Vec::new();
    if let Some(rows_path) = rows_path {
        let text = match std::fs::read_to_string(rows_path) {
            Ok(text) => text,
            Err(err) => {
                eprintln!("{prefix}: {rows_path}: {err}");
                return 1;
            }
        };
        for line in text.split('\n') {
            if !line.trim().is_empty() {
                plugin_rows.push(line.trim_end_matches('\n').to_string());
            }
        }
    }

    let spec: Option<Value> = match presets_path {
        Some(presets_path) => {
            let text = match std::fs::read_to_string(presets_path) {
                Ok(text) => text,
                Err(err) => {
                    eprintln!("{prefix}: {presets_path}: {err}");
                    return 1;
                }
            };
            match serde_json::from_str(&text) {
                Ok(spec) => Some(spec),
                Err(err) => {
                    eprintln!("{prefix}: {presets_path}: {err}");
                    return 1;
                }
            }
        }
        None => None,
    };

    let mut blocks: Vec<Vec<String>> = Vec::new();
    if let Some(spec) = &spec {
        match preset_block(spec, &marker_presets) {
            Ok(block) => blocks.push(block),
            Err(message) => {
                eprintln!("{message}");
                return 1;
            }
        }
    }

    let registry_row = spec
        .as_ref()
        .and_then(|spec| spec["registryRow"].as_str())
        .unwrap_or("dsh-tui-agent-preset-registry");
    let default_preset = spec
        .as_ref()
        .and_then(|spec| spec["defaultPreset"].as_str())
        .unwrap_or("neg");
    blocks.push(vec![
        format!(
            "{marker_preset} — the shipped `standard` belongs to the web-app bundle, which this"
        ),
        "# profile does not mount, so the registry default must name a preset the".to_string(),
        "# profile declares. settings.yaml still overrides it at runtime (the".to_string(),
        "# registry reads its settings-backed `selectedDefault` first).".to_string(),
        format!("- id: {registry_row}"),
        "  config:".to_string(),
        format!("    default: {default_preset}"),
    ]);

    let mut plugin_block = vec![marker_plugins.clone()];
    plugin_block.extend(plugin_rows.iter().cloned());
    blocks.push(plugin_block);

    let mut legacy_block = vec![
        format!("{marker_legacy} — 0.1.5-era plugin packages this harness generation rejects;"),
        "# disabled here instead of letting the boot warn about each one.".to_string(),
    ];
    for row in ["dsh-tui-agent-presets", "dsh-tui-code-runtime"] {
        legacy_block.push(format!("- id: {row}"));
        legacy_block.push("  disabled: true".to_string());
    }
    blocks.push(legacy_block);

    let src = match std::fs::read_to_string(path) {
        Ok(src) => src,
        Err(err) => {
            eprintln!("{prefix}: {path}: {err}");
            return 1;
        }
    };
    let lines: Vec<&str> = src.split('\n').collect();
    let mut header: Vec<&str> = Vec::new();
    let mut kept: Vec<&str> = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        let line = lines[index];
        if owned_markers.iter().any(|marker| line.contains(marker)) {
            // Skip this block: its marker line plus everything up to the next
            // block we own (or EOF).
            index += 1;
            while index < lines.len()
                && !owned_markers
                    .iter()
                    .any(|marker| lines[index].contains(marker))
            {
                index += 1;
            }
            continue;
        }
        if line.trim() == "[]" {
            index += 1;
            continue;
        }
        if kept.is_empty() && line.starts_with('#') {
            header.push(line);
        } else {
            kept.push(line);
        }
        index += 1;
    }

    let mut body = header.join("\n");
    body = body.trim_end_matches('\n').to_string();
    for block in &blocks {
        body.push_str("\n\n");
        body.push_str(&block.join("\n"));
    }
    body = format!("{}\n", body.trim_end_matches('\n'));
    let extra: Vec<&str> = kept
        .iter()
        .copied()
        .filter(|row| !row.trim().is_empty() && !row.starts_with('#'))
        .collect();
    if !extra.is_empty() {
        body = format!("{}\n{}\n", body.trim_end_matches('\n'), extra.join("\n"));
    }

    if body == src {
        println!("{prefix}: {path}: profile layer already current");
        return 0;
    }
    if let Err(err) = std::fs::write(path, &body) {
        eprintln!("{prefix}: {path}: {err}");
        return 1;
    }
    println!("{prefix}: {path}: wrote the profile layer (presets + plugin rows)");
    0
}

fn preset_block(spec: &Value, marker_presets: &str) -> Result<Vec<String>, String> {
    let declaration_plugin = spec["declarationPlugin"].as_str().unwrap_or_default();
    let mut lines = vec![
        format!("{marker_presets} — declaration rows (@deepseek-ai/dsh-agent-preset). The old"),
        "# $DSH_HOME/.agent-presets/<id>/ directories are dead in 0.2.0; see".to_string(),
        "# modules/user/nix-maid/apps/dsh-presets.nix for the source of truth.".to_string(),
    ];
    let presets = spec["presets"].as_array().cloned().unwrap_or_default();
    for preset in presets {
        let id = preset["id"].as_str().unwrap_or_default();
        let plugins_path = preset["plugins"].as_str().unwrap_or_default();
        let text = std::fs::read_to_string(plugins_path)
            .map_err(|err| format!("dsh-tui-preset: {plugins_path}: {err}"))?;
        let mut plugins: Vec<&str> = text.split('\n').collect();
        while plugins
            .first()
            .map(|line| line.trim().is_empty() || line.trim_start().starts_with('#'))
            .unwrap_or(false)
        {
            plugins.remove(0);
        }
        while plugins
            .last()
            .map(|line| line.trim().is_empty())
            .unwrap_or(false)
        {
            plugins.pop();
        }

        lines.push("- insert:".to_string());
        lines.push(format!("    - id: preset-{id}"));
        lines.push(format!("      name: '{declaration_plugin}'"));
        lines.push("      config:".to_string());
        lines.push(format!("        id: {id}"));
        lines.push(format!(
            "        name: {}",
            json_string(preset["name"].as_str().unwrap_or_default())
        ));
        lines.push(format!(
            "        description: {}",
            json_string(preset["description"].as_str().unwrap_or_default())
        ));
        lines.push(format!(
            "        order: {}",
            preset["order"].as_i64().unwrap_or_default()
        ));
        lines.push("        plugins:".to_string());
        for line in plugins {
            if line.trim().is_empty() {
                lines.push(String::new());
            } else {
                lines.push(format!("{}{}", " ".repeat(10), line).trim_end().to_string());
            }
        }
    }
    Ok(lines)
}

/// `json.dumps(text, ensure_ascii=False)`: a JSON string literal.
fn json_string(text: &str) -> String {
    serde_json::to_string(text).unwrap_or_else(|_| format!("\"{text}\""))
}
