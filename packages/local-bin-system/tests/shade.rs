//! Hermetic tests for the `shade` port: the `hyprctl eval` expression, the
//! shader listing/resolution, the fzf picker contract and the plugin-loaded
//! gate. `hyprctl` and `fzf` are fakes that record their argv and stdin.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_shade");

const HYPRCTL: &str = r#"#!/bin/sh
if [ "$1" = "plugin" ]; then
  printf '%s\n' "${FAKE_PLUGIN-HyprWindowShade}"
  exit "${FAKE_PLUGIN_CODE:-0}"
fi
printf '%s\n' "$*" >> "$FAKE_ARGV_LOG"
printf 'dispatcher noise\n' >&2
exit "${FAKE_EVAL_CODE:-1}"
"#;

const FZF: &str = r#"#!/bin/sh
while IFS= read -r line; do printf '%s\n' "$line" >> "$FAKE_DMENU_IN"; done
printf '%s' "${FAKE_SEL:-}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("hyprctl", HYPRCTL);
    case
}

fn shader(case: &Case, name: &str, description: Option<&str>) {
    let directory = case.home.join(".config/hypr/shaders");
    let body = match description {
        Some(description) => format!("// HyprWindowShade: {description}\nvoid main() {{}}\n"),
        None => "// nothing here\nvoid main() {}\n".to_string(),
    };
    case.write(&directory.join(name), &body);
}

fn eval_argv(case: &Case) -> String {
    case.argv_log()
}

#[test]
fn help_matches_the_header() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let text = stdout(&output);
    assert!(text.starts_with("shade — HyprWindowShade: fragment shaders on windows and layers.\n"));
    assert!(text.contains("  shade class CLASS [NAME]  toggle NAME for every window of CLASS"));
    // The header range stops after the `hyprctl eval, not` line.
    assert!(text
        .ends_with("after hyprwindowshade-setup has dlopen'd the .so — hence hyprctl eval, not\n"));
}

#[test]
fn missing_hyprctl_is_fatal_even_for_help() {
    let case = Case::new("no-hyprctl", BIN);
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "shade: missing dependency: hyprctl\n");
}

#[test]
fn list_prints_padded_names_and_first_description_line() {
    let case = fixture("list");
    shader(&case, "crt.glsl", Some("CRT scanlines"));
    shader(&case, "dim.glsl", Some("dim it"));
    shader(&case, "plain.glsl", None);
    // Hidden shaders and non-glsl files are not part of the `*.glsl` glob.
    shader(&case, ".hidden.glsl", Some("hidden"));
    case.write(
        &case.home.join(".config/hypr/shaders/readme.txt"),
        "not a shader",
    );

    let output = case.run(&["list"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "crt             CRT scanlines\ndim             dim it\nplain           \n"
    );
    assert_eq!(stderr(&output), "");
}

#[test]
fn list_without_directory_dies() {
    let case = fixture("list-missing");
    let output = case.run(&["list"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "shade: shader directory not found: {}/.config/hypr/shaders\n",
            case.home.to_string_lossy()
        )
    );
}

#[test]
fn xdg_config_home_selects_the_shader_directory() {
    let case = fixture("xdg");
    let directory = case.path("xdg/hypr/shaders");
    case.write(&directory.join("crt.glsl"), "// HyprWindowShade: CRT\n");
    let output = case.run_env(
        &["list"],
        &[("XDG_CONFIG_HOME", &case.path("xdg").to_string_lossy())],
    );
    assert_eq!(stdout(&output), "crt             CRT\n");
}

#[test]
fn on_toggles_the_focused_window_with_a_quoted_path() {
    let case = fixture("on");
    shader(&case, "crt.glsl", Some("CRT"));
    let output = case.run(&["on", "crt"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "shade: crt.glsl → focused window (again to remove)\n"
    );
    assert_eq!(
        eval_argv(&case),
        format!(
            "eval hl.plugin.HyprWindowShade.togglewindowshader(\"{}/.config/hypr/shaders/crt.glsl\")\n",
            case.home.to_string_lossy()
        )
    );
}

#[test]
fn on_accepts_the_glsl_suffix_and_absolute_paths() {
    let case = fixture("on-suffix");
    shader(&case, "crt.glsl", Some("CRT"));
    let with_suffix = case.run(&["on", "crt.glsl"]);
    assert_eq!(exited(&with_suffix), 0);

    let absolute = case.home.join(".config/hypr/shaders/crt.glsl");
    let output = case.run(&["on", &absolute.to_string_lossy()]);
    assert_eq!(exited(&output), 0);
    let argv = eval_argv(&case);
    assert!(argv.contains(&absolute.to_string_lossy().into_owned()));
}

#[test]
fn resolve_reports_missing_shaders_with_hints_and_continues() {
    let case = fixture("resolve");
    shader(&case, "crt.glsl", Some("CRT"));

    // `path=$(resolve "$pick")` runs resolve in a subshell: the warning goes
    // to stderr and the action continues with an empty path (the original's
    // observable behaviour).
    let missing = case.run(&["on", "nope"]);
    assert_eq!(exited(&missing), 0);
    assert_eq!(
        stderr(&missing),
        "shade: no such shader: nope (see 'shade list')\n"
    );
    assert_eq!(
        stdout(&missing),
        "shade:  → focused window (again to remove)\n"
    );
    assert!(eval_argv(&case).contains("togglewindowshader(\"\")"));

    let relative = case.run(&["on", "dir/nope.glsl"]);
    assert_eq!(exited(&relative), 0);
    assert_eq!(stderr(&relative), "shade: no such shader: dir/nope.glsl\n");

    let absolute = case.run(&["on", "/definitely/nope.glsl"]);
    assert_eq!(exited(&absolute), 0);
    assert_eq!(
        stderr(&absolute),
        "shade: no such shader: /definitely/nope.glsl\n"
    );
}

#[test]
fn on_without_a_name_uses_the_fzf_picker() {
    let case = fixture("fzf");
    case.write_fake("fzf", FZF);
    shader(&case, "crt.glsl", Some("CRT"));
    shader(&case, "dim.glsl", Some("dim it"));

    let output = case.run_env(&["on"], &[("FAKE_SEL", "dim             dim it\n")]);
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("shade: dim.glsl → focused window"));
    assert!(eval_argv(&case).contains("\"dim.glsl\"") || eval_argv(&case).contains("dim.glsl"));
    assert_eq!(
        case.read("dmenu-in.log"),
        "crt             CRT\ndim             dim it\n"
    );
}

#[test]
fn fzf_cancel_exits_quietly() {
    let case = fixture("fzf-cancel");
    case.write_fake("fzf", FZF);
    shader(&case, "crt.glsl", Some("CRT"));
    let output = case.run(&["on"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv_log(), "");
}

#[test]
fn on_without_fzf_lists_and_fails() {
    let case = fixture("no-fzf");
    shader(&case, "crt.glsl", Some("CRT"));
    let output = case.run(&["on"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "crt             CRT\n");
    assert_eq!(stderr(&output), "shade: name a shader, e.g. shade on crt\n");
}

#[test]
fn fzf_without_a_shader_directory_loses_its_subshell_only() {
    let case = fixture("fzf-missing-dir");
    case.write_fake("fzf", FZF);
    let output = case.run(&["on"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert!(stderr(&output).contains("shader directory not found"));
}

#[test]
fn off_clears_the_focused_window() {
    let case = fixture("off");
    let output = case.run(&["off"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "shade: cleared the focused window\n");
    assert_eq!(
        eval_argv(&case),
        "eval hl.plugin.HyprWindowShade.togglewindowshader(\"clear\")\n"
    );
}

#[test]
fn class_and_layer_actions_use_the_plugin_call_forms() {
    let case = fixture("class-layer");
    shader(&case, "crt.glsl", Some("CRT"));

    let class_set = case.run(&["class", "foot", "crt"]);
    assert_eq!(exited(&class_set), 0);
    assert_eq!(stdout(&class_set), "shade: crt.glsl → class foot\n");
    assert!(eval_argv(&case).contains("toggleclassshader(\"foot\","));

    let class_clear = case.run(&["class", "foot"]);
    assert_eq!(stdout(&class_clear), "shade: cleared class foot\n");

    let layer_set = case.run(&["layer", "rofi", "crt"]);
    assert_eq!(stdout(&layer_set), "shade: crt.glsl → layer rofi\n");

    let layer_clear = case.run(&["layer", "rofi"]);
    assert_eq!(stdout(&layer_clear), "shade: cleared layer rofi\n");
    let argv = eval_argv(&case);
    assert!(argv.contains("classshader(\"foot\",\"clear\")"));
    assert!(argv.contains("togglelayershader(\"rofi\","));
    assert!(argv.contains("layershader(\"rofi\",\"clear\")"));
}

#[test]
fn class_and_layer_require_a_target() {
    let case = fixture("usage");
    for (arguments, message) in [
        (vec!["class"], "shade: usage: shade class CLASS [NAME]\n"),
        (
            vec!["layer"],
            "shade: usage: shade layer NAMESPACE [NAME]\n",
        ),
    ] {
        let output = case.run(&arguments);
        assert_eq!(exited(&output), 1);
        assert_eq!(stderr(&output), message);
    }
}

#[test]
fn reload_drops_the_shader_cache() {
    let case = fixture("reload");
    let output = case.run(&["reload"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "shade: shader cache dropped, .glsl files re-read\n"
    );
    assert_eq!(
        eval_argv(&case),
        "eval hl.plugin.HyprWindowShade.reloadshaders()\n"
    );
}

#[test]
fn the_plugin_must_be_loaded() {
    let case = fixture("not-loaded");
    let output = case.run_env(&["reload"], &[("FAKE_PLUGIN", "SomethingElse")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "shade: plugin is not loaded — run hyprwindowshade-setup\n"
    );
}

#[test]
fn quotes_and_backslashes_are_refused() {
    let case = fixture("quoting");
    let quote = case.run(&["class", "a\"b"]);
    assert_eq!(exited(&quote), 1);
    assert_eq!(
        stderr(&quote),
        "shade: argument contains a quote or backslash: a\"b\n"
    );

    let backslash = case.run(&["class", "a\\b"]);
    assert_eq!(exited(&backslash), 1);
    assert_eq!(
        stderr(&backslash),
        "shade: argument contains a quote or backslash: a\\b\n"
    );
}

#[test]
fn unknown_commands_print_usage_then_die() {
    let case = fixture("unknown");
    let output = case.run(&["bogus"]);
    assert_eq!(exited(&output), 1);
    assert!(stdout(&output).contains("shade — HyprWindowShade"));
    assert_eq!(stderr(&output), "shade: unknown command: bogus\n");
}

#[test]
fn no_arguments_lists_shaders() {
    let case = fixture("default");
    shader(&case, "crt.glsl", Some("CRT"));
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "crt             CRT\n");
}

#[test]
fn long_names_are_not_truncated() {
    let case = fixture("long-name");
    let name = "very-long-shader-name.glsl";
    shader(&case, name, Some("desc"));
    let output = case.run(&["list"]);
    assert_eq!(stdout(&output), "very-long-shader-name desc\n");
}

#[test]
fn help_question_mark_is_a_command_alias() {
    let case = fixture("question");
    let output = case.run(&["?"]);
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).starts_with("shade — HyprWindowShade"));
}
