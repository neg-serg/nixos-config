//! Golden parity tests against the extracted Python oracle.
//!
//! The goldens under `tests/fixtures/golden/` were produced by the original
//! embedded Python programs (see `tests/reference/README.md`); this file only
//! compares the Rust output against those committed bytes. No Python is needed
//! at test time, so `cargo test` works in the Nix build sandbox.

mod common;

use common::{fixture, shell_mode, TestDir};
use serde_json::Value;
use sing_box_proxy::config::{build_config, patch_config, write_config, write_config_in_place};
use sing_box_proxy::jsonout::to_python_json;
use std::fs;

fn render_logs(logs: &[String]) -> String {
    if logs.is_empty() {
        String::new()
    } else {
        format!("{}\n", logs.join("\n"))
    }
}

fn lan_auth(fixture_path: &str) -> String {
    fixture(fixture_path).trim_end_matches('\n').to_string()
}

#[test]
fn generated_configs_match_the_python_generator() {
    let cases: [(&str, &str, Option<&str>, &str, i32); 5] = [
        ("mixed_nolan", "nodes/mixed.txt", None, "lan/empty.txt", 0),
        ("mixed_lan", "nodes/mixed.txt", None, "lan/lan_on.txt", 0),
        ("edge_nolan", "nodes/edge.txt", None, "lan/empty.txt", 0),
        (
            "mixed_tg",
            "nodes/mixed.txt",
            Some("tg/tg_mixed.txt"),
            "lan/empty.txt",
            0,
        ),
        ("no_nodes", "nodes/no_nodes.txt", None, "lan/empty.txt", 1),
    ];
    for (case, nodes_path, tg_path, lan_path, expected_exit) in cases {
        let nodes = fixture(nodes_path);
        let tg = tg_path.map(fixture).unwrap_or_default();
        let outcome = build_config(&nodes, &tg, &lan_auth(lan_path));
        assert_eq!(outcome.exit_code, expected_exit, "exit code for {case}");
        assert_eq!(
            render_logs(&outcome.logs),
            fixture(&format!("golden/gen/{case}.stderr")),
            "stderr for {case}"
        );
        match outcome.config {
            Some(config) => assert_eq!(
                to_python_json(&config),
                fixture(&format!("golden/gen/{case}.json")),
                "config bytes for {case}"
            ),
            None => assert!(
                !std::path::Path::new(&format!(
                    "{}/tests/fixtures/golden/gen/{case}.json",
                    env!("CARGO_MANIFEST_DIR")
                ))
                .exists(),
                "{case} must not have a config golden"
            ),
        }
    }
}

#[test]
fn bootstrap_patcher_matches_the_python_patcher() {
    let cases: [(&str, &str); 6] = [
        ("old_no_tg", "lan/lan_on.txt"),
        ("empty_tg", "lan/empty.txt"),
        ("final_noop", "lan/lan_on.txt"),
        ("lan_sync", "lan/lan_on.txt"),
        ("lan_remove", "lan/empty.txt"),
        ("reordered_dns", "lan/empty.txt"),
    ];
    for (case, lan_path) in cases {
        let input = fixture(&format!("bootstrap/{case}.json"));
        let mut config: Value = serde_json::from_str(&input).expect("fixture json");
        let outcome = patch_config(&mut config, &lan_auth(lan_path)).expect("patch");
        let rendered = to_python_json(&config);
        assert_eq!(
            rendered,
            fixture(&format!("golden/bootstrap/{case}.json")),
            "patched config for {case}"
        );
        let expected_messages: Vec<String> = fixture(&format!("golden/bootstrap/{case}.stderr"))
            .lines()
            .filter(|line| line.starts_with(":: "))
            .map(|line| line.to_string())
            .collect();
        assert_eq!(outcome.logs, expected_messages, "messages for {case}");
        assert_eq!(
            outcome.changed,
            rendered != input,
            "changed flag for {case}"
        );
    }
}

#[test]
fn config_files_are_written_with_python_bytes_and_private_modes() {
    let dir = TestDir::new("modes");
    let config_path = dir.join("nested/config.json");
    let outcome = build_config(&fixture("nodes/mixed.txt"), "", &lan_auth("lan/lan_on.txt"));
    let config = outcome.config.expect("config");
    write_config(&config_path, &config).expect("write config");

    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        fixture("golden/gen/mixed_lan.json")
    );
    assert_eq!(shell_mode(&config_path), 0o600, "file mode");
    assert_eq!(
        shell_mode(config_path.parent().unwrap()),
        0o700,
        "directory mode"
    );

    // Healing an existing config enforces 0600 too.
    fs::set_permissions(
        &config_path,
        std::os::unix::fs::PermissionsExt::from_mode(0o644),
    )
    .unwrap();
    write_config_in_place(&config_path, &config).expect("rewrite config");
    assert_eq!(shell_mode(&config_path), 0o600, "rewritten file mode");
}
