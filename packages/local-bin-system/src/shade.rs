//! shade — HyprWindowShade: fragment shaders on windows and layers.
//!
//! Port of `packages/local-bin/bin/shade` (POSIX sh). The plugin exposes its
//! actions only through its Lua namespace, which exists after
//! hyprwindowshade-setup has dlopen'd the .so — hence `hyprctl eval`, not
//! `dispatch`.
//!
//! Kept from the original: the exact `hyprctl eval` expression (arguments are
//! `"`-quoted and comma-joined), the quote/backslash refusal, the shader
//! listing format, the fzf picker invocation `fzf --prompt 'shader> '` with
//! `awk '{print $1}'` selection, and every message.

use std::fs;
use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_system as sh;

const USAGE: &str = "shade — HyprWindowShade: fragment shaders on windows and layers.

  shade list                list ~/.config/hypr/shaders (name + one-line description)
  shade on [NAME]           toggle NAME on the focused window; without NAME an
                            fzf picker opens (and falls back to listing them)
  shade off                 strip every shader from the focused window
  shade class CLASS [NAME]  toggle NAME for every window of CLASS; without NAME
                            it clears that class
  shade layer NS [NAME]     toggle NAME for a layer namespace (rofi, mpvpaper, …)
  shade reload              re-read every .glsl from disk

NAME is a shader in ~/.config/hypr/shaders, with or without the .glsl suffix;
an absolute path works too. Shaders are HyprShade-compatible GLSL ES 3.20 and
are re-read every frame, so editing one needs no reload.

The plugin exposes its actions only through its Lua namespace, which exists
after hyprwindowshade-setup has dlopen'd the .so — hence hyprctl eval, not
";

fn prog() -> String {
    sh::prog("shade")
}

fn die(message: &str) -> ! {
    sh::die(&prog(), message)
}

fn shader_dir() -> String {
    format!(
        "{}/hypr/shaders",
        sh::env_or("XDG_CONFIG_HOME", &format!("{}/.config", sh::home()))
    )
}

fn usage() {
    sh::out_str(USAGE);
}

/// `shade_call FN ARG…` — run a plugin action, ignoring the dispatcher noise
/// the plugin cannot avoid (it reports a failure even when the action landed).
fn shade_call(function: &str, arguments: &[String]) {
    let mut joined = String::new();
    for argument in arguments {
        if sh::has_quote_or_backslash(argument) {
            die(&format!(
                "argument contains a quote or backslash: {argument}"
            ));
        }
        if !joined.is_empty() {
            joined.push(',');
        }
        joined.push('"');
        joined.push_str(argument);
        joined.push('"');
    }
    let expression = format!("hl.plugin.HyprWindowShade.{function}({joined})");
    let _ = sh::run_quiet("hyprctl", &["eval", &expression]);
}

fn plugin_loaded() {
    let listed = sh::capture("hyprctl", &["plugin", "list"], true);
    let found = listed
        .map(|output| String::from_utf8_lossy(&output.stdout).contains("HyprWindowShade"))
        .unwrap_or(false);
    if !found {
        die("plugin is not loaded — run hyprwindowshade-setup");
    }
}

struct Shader {
    name: String,
    description: String,
}

fn list_shaders() -> Result<Vec<Shader>, String> {
    let directory = shader_dir();
    let path = Path::new(&directory);
    if !path.is_dir() {
        return Err(format!("shader directory not found: {directory}"));
    }
    let mut shaders = Vec::new();
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let file_name = entry.file_name().to_string_lossy().into_owned();
            if file_name.starts_with('.') || !file_name.ends_with(".glsl") {
                continue;
            }
            if !entry.path().is_file() {
                continue;
            }
            let name = file_name
                .strip_suffix(".glsl")
                .unwrap_or(&file_name)
                .to_string();
            let description = sh::read_text(&entry.path())
                .unwrap_or_default()
                .lines()
                .find_map(|line| {
                    line.strip_prefix("// HyprWindowShade: ")
                        .map(str::to_string)
                })
                .unwrap_or_default();
            shaders.push(Shader { name, description });
        }
    }
    shaders.sort_by(|left, right| left.name.as_bytes().cmp(right.name.as_bytes()));
    Ok(shaders)
}

fn print_shaders(shaders: &[Shader]) {
    for shader in shaders {
        sh::out_str_line(&format!("{:<15} {}", shader.name, shader.description));
    }
}

fn list_command() {
    match list_shaders() {
        Ok(shaders) => print_shaders(&shaders),
        Err(message) => die(&message),
    }
}

/// Resolve NAME — print the shader path, or report the hint. The original
/// calls this from `path=$(resolve "$pick")`, so a missing shader only kills
/// the command-substitution subshell: the warning goes to stderr and the
/// caller continues with an empty path (which the plugin then sees as `""`).
fn resolve(argument: &str) -> Option<String> {
    let report = |message: String| -> Option<String> {
        sh::err_line(&format!("{}: {message}", prog()));
        None
    };
    if argument.starts_with('/') && argument.ends_with(".glsl") {
        if !Path::new(argument).is_file() {
            return report(format!("no such shader: {argument}"));
        }
        return Some(argument.to_string());
    }
    if argument.contains('/') {
        return report(format!("no such shader: {argument}"));
    }
    let name = argument.strip_suffix(".glsl").unwrap_or(argument);
    let path = format!("{}/{name}.glsl", shader_dir());
    if !Path::new(&path).is_file() {
        return report(format!("no such shader: {name} (see 'shade list')"));
    }
    Some(path)
}

fn shader_basename(path: &str) -> String {
    path.rsplit('/').next().unwrap_or(path).to_string()
}

/// `pick=$(list_shaders | fzf --prompt 'shader> ' | awk '{print $1}')` — the
/// picker runs in a pipeline whose failing first stage only loses its own
/// subshell, so a missing shader directory is not fatal here.
fn pick_with_fzf() -> String {
    let shaders = match list_shaders() {
        Ok(shaders) => shaders,
        Err(message) => {
            sh::err_line(&format!("{}: {message}", prog()));
            std::process::exit(0);
        }
    };
    let mut input = String::new();
    for shader in &shaders {
        input.push_str(&format!("{:<15} {}\n", shader.name, shader.description));
    }

    let mut child = match Command::new("fzf")
        .args(["--prompt", "shader> "])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return String::new(),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }
    let mut output = String::new();
    if let Some(mut stdout) = child.stdout.take() {
        let _ = stdout.read_to_string(&mut output);
    }
    let _ = child.wait();
    // awk '{print $1}' per line, then the command substitution strips the
    // trailing newlines.
    let mut picked = String::new();
    for line in output.split('\n') {
        if !picked.is_empty() {
            picked.push('\n');
        }
        picked.push_str(line.split_whitespace().next().unwrap_or(""));
    }
    picked.trim_end_matches('\n').to_string()
}

fn command_on(rest: &[String]) {
    plugin_loaded();
    let mut pick = rest.first().filter(|value| !value.is_empty()).cloned();
    if pick.is_none() {
        if sh::which("fzf").is_some() {
            let selected = pick_with_fzf();
            if selected.is_empty() {
                return;
            }
            pick = Some(selected);
        } else {
            list_command();
            die("name a shader, e.g. shade on crt");
        }
    }
    let path = resolve(&pick.unwrap_or_default()).unwrap_or_default();
    shade_call("togglewindowshader", std::slice::from_ref(&path));
    sh::out_str_line(&format!(
        "shade: {} → focused window (again to remove)",
        shader_basename(&path)
    ));
}

fn command_off() {
    plugin_loaded();
    shade_call("togglewindowshader", &["clear".to_string()]);
    sh::out_str_line("shade: cleared the focused window");
}

fn command_class(rest: &[String]) {
    plugin_loaded();
    let Some(class) = rest.first().filter(|value| !value.is_empty()) else {
        die("usage: shade class CLASS [NAME]");
    };
    match rest.get(1).filter(|value| !value.is_empty()) {
        Some(name) => {
            let path = resolve(name).unwrap_or_default();
            shade_call("toggleclassshader", &[class.clone(), path.clone()]);
            sh::out_str_line(&format!(
                "shade: {} → class {class}",
                shader_basename(&path)
            ));
        }
        None => {
            shade_call("classshader", &[class.clone(), "clear".to_string()]);
            sh::out_str_line(&format!("shade: cleared class {class}"));
        }
    }
}

fn command_layer(rest: &[String]) {
    plugin_loaded();
    let Some(namespace) = rest.first().filter(|value| !value.is_empty()) else {
        die("usage: shade layer NAMESPACE [NAME]");
    };
    match rest.get(1).filter(|value| !value.is_empty()) {
        Some(name) => {
            let path = resolve(name).unwrap_or_default();
            shade_call("togglelayershader", &[namespace.clone(), path.clone()]);
            sh::out_str_line(&format!(
                "shade: {} → layer {namespace}",
                shader_basename(&path)
            ));
        }
        None => {
            shade_call("layershader", &[namespace.clone(), "clear".to_string()]);
            sh::out_str_line(&format!("shade: cleared layer {namespace}"));
        }
    }
}

fn command_reload() {
    plugin_loaded();
    shade_call("reloadshaders", &[]);
    sh::out_str_line("shade: shader cache dropped, .glsl files re-read");
}

fn main() {
    sh::require(&prog(), "hyprctl");
    let arguments = sh::args();
    let command = arguments
        .first()
        .filter(|value| !value.is_empty())
        .cloned()
        .unwrap_or_else(|| "list".to_string());
    let rest = if arguments.is_empty() {
        Vec::new()
    } else {
        arguments[1..].to_vec()
    };
    match command.as_str() {
        "-h" | "--help" | "help" | "?" => usage(),
        "list" | "ls" => list_command(),
        "on" | "toggle" => command_on(&rest),
        "off" | "clear" => command_off(),
        "class" => command_class(&rest),
        "layer" => command_layer(&rest),
        "reload" => command_reload(),
        other => {
            usage();
            die(&format!("unknown command: {other}"));
        }
    }
}
