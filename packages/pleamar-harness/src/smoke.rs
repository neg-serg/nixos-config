//! `pleamar-smoke`, the port of `files/pleamar/scripts/smoke.sh`.
//!
//! Compiles every scene with `pleamar --check` and renders one PNG per scene
//! through `pleamar-wm headless` or a nested headless wlroots compositor with
//! `grim`. Part files are skipped; a failed compile, a missing/truncated PNG or
//! a non-zero renderer exit is exit 1, a missing renderer without
//! `--require-render` is a `no-renderer` column and exit 0.

use std::env;
use std::fs;
use std::io::Write;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::ctx::{Ctx, Halt};
use crate::proc;
use crate::scene;
use crate::text;
use crate::usage;

pub struct Options {
    pub scene: Option<String>,
    pub seconds: String,
    pub out: Option<PathBuf>,
    pub require_render: bool,
    pub live: bool,
    pub keep_tmp: bool,
    pub min_bytes: String,
    pub soft: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            scene: None,
            seconds: "8".to_string(),
            out: None,
            require_render: false,
            live: false,
            keep_tmp: false,
            min_bytes: "1024".to_string(),
            soft: false,
        }
    }
}

pub enum Parsed {
    Help,
    Run(Options),
}

pub fn parse_args(args: &[String]) -> Result<Parsed, Halt> {
    let mut options = Options::default();
    let mut index = 0usize;
    while index < args.len() {
        let argument = &args[index];
        match argument.as_str() {
            "--scene" => {
                options.scene = Some(need_value(args, index, "--scene needs a scene name")?);
                index += 2;
            }
            "--seconds" => {
                options.seconds = need_value(args, index, "--seconds needs a number")?;
                index += 2;
            }
            "--out" => {
                options.out = Some(PathBuf::from(need_value(
                    args,
                    index,
                    "--out needs a directory",
                )?));
                index += 2;
            }
            "--min-bytes" => {
                options.min_bytes = need_value(args, index, "--min-bytes needs a number")?;
                index += 2;
            }
            "--require-render" => {
                options.require_render = true;
                index += 1;
            }
            "--live" => {
                options.live = true;
                index += 1;
            }
            "--keep-tmp" => {
                options.keep_tmp = true;
                index += 1;
            }
            "--soft" => {
                options.soft = true;
                index += 1;
            }
            "-h" | "--help" => return Ok(Parsed::Help),
            other => {
                return Err(Halt::Die(format!("unknown argument: {other} (try --help)")));
            }
        }
    }
    require_uint(&options.seconds, "--seconds")?;
    require_uint(&options.min_bytes, "--min-bytes")?;
    let seconds: u64 = options.seconds.parse().unwrap_or(1);
    if seconds < 2 {
        return Err(Halt::Die(
            "--seconds must be at least 2 for a shot to fit in the session".to_string(),
        ));
    }
    Ok(Parsed::Run(options))
}

fn need_value(args: &[String], index: usize, message: &str) -> Result<String, Halt> {
    match args.get(index + 1) {
        Some(value) => Ok(value.clone()),
        None => Err(Halt::Die(message.to_string())),
    }
}

fn require_uint(value: &str, name: &str) -> Result<(), Halt> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(Halt::Die(format!(
            "{name} must be a positive integer (got '{value}')"
        )));
    }
    match value.parse::<u64>() {
        Ok(number) if number >= 1 => Ok(()),
        _ => Err(Halt::Die(format!("{name} must be at least 1"))),
    }
}

pub fn say_usage() {
    print!("{}", usage::SMOKE);
}

struct Renderer {
    name: String,
    bin: String,
    grim: Option<String>,
}

pub fn run(ctx: &mut Ctx, options: Options) -> Result<i32, Halt> {
    ctx.keep_tmp = options.keep_tmp;
    let pleamar_name = env_or("PLEAMAR_BIN", "pleamar");
    let wm_name = env_or("PLEAMAR_WM_BIN", "pleamar-wm");
    let pleamar = match ctx.resolve_bin(&pleamar_name) {
        Some(path) => path,
        None => {
            return ctx.die(format!(
                "pleamar not found (PLEAMAR_BIN='{pleamar_name}'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar"
            ))
        }
    };
    let seconds: u64 = options.seconds.parse().unwrap_or(2);
    let min_bytes: u64 = options.min_bytes.parse().unwrap_or(1024);
    let seconds_text = options.seconds.clone();
    let min_text = options.min_bytes.clone();
    let hit = seconds.saturating_sub(2).clamp(1, 4);

    setup_env(ctx, options.live)?;
    crate::env::apply_soft(ctx, options.soft);

    let mut scenes: Vec<(String, PathBuf)> = Vec::new();
    for file in scene::scene_files(&ctx.project) {
        if scene::is_part_file(&file) {
            let relative = file
                .strip_prefix(&ctx.project)
                .unwrap_or(&file)
                .to_string_lossy()
                .into_owned();
            ctx.say(format!("skipping part file: {relative}"));
            continue;
        }
        let name = scene::scene_name_of(&file);
        if let Some(filter) = options.scene.as_deref() {
            if name != filter {
                continue;
            }
        }
        scenes.push((name, file));
    }
    if scenes.is_empty() {
        if let Some(filter) = options.scene.as_deref() {
            return ctx.die(format!(
                "no scene named '{filter}' under {} (expected shells/<scene>/<scene>.plm)",
                ctx.project.join("shells").display()
            ));
        }
        return ctx.die(format!(
            "no scenes found under {}/*/*.plm; nothing to smoke",
            ctx.project.join("shells").display()
        ));
    }

    let renderer = detect_renderer(ctx);
    if renderer.is_none() {
        if options.require_render {
            return ctx.die(format!(
                "no renderer available: tried pleamar-wm (PLEAMAR_WM_BIN='{wm_name}') and headless 'sway'/'cage' with 'grim'; install pleamar-wm (or a nested compositor plus grim), or drop --require-render to run the compile matrix only"
            ));
        }
        ctx.warn(format!(
            "no renderer available: tried pleamar-wm (PLEAMAR_WM_BIN='{wm_name}') and headless 'sway'/'cage' with 'grim'; rendering is skipped (pass --require-render to make this fatal)"
        ));
    }

    let out_dir = options
        .out
        .clone()
        .unwrap_or_else(|| ctx.project.join("tests/shots"));
    let shot_dir = out_dir.join(crate::env::date("+%Y-%m-%d"));
    if renderer.is_some() {
        if let Err(error) = fs::create_dir_all(&shot_dir) {
            return ctx.fail(format!("cannot create {}: {error}", shot_dir.display()));
        }
    }

    let mut names: Vec<String> = Vec::new();
    let mut check_states: Vec<String> = Vec::new();
    let mut render_states: Vec<String> = Vec::new();
    let mut png_sizes: Vec<String> = Vec::new();
    let mut notes: Vec<String> = Vec::new();
    let mut failed = false;
    let mut rendered_ok = 0usize;

    for (name, file) in &scenes {
        names.push(name.clone());
        let render_state;
        let mut png_size = "-".to_string();
        let mut note;
        let check_file = ctx.temp().join("check.out");
        let check_status = proc::output_merged(
            &pleamar,
            &[
                std::ffi::OsString::from("--check"),
                file.as_os_str().to_os_string(),
            ],
            &check_file,
        );
        let check_out = fs::read(&check_file).unwrap_or_default();
        let check_out = String::from_utf8_lossy(&check_out)
            .trim_end_matches('\n')
            .to_string();
        let first = check_out.lines().next().unwrap_or("").to_string();
        let check_state = if check_status.map(|status| status.success()).unwrap_or(false) {
            "ok".to_string()
        } else {
            failed = true;
            "FAIL".to_string()
        };
        note = first;

        if let Some(renderer) = &renderer {
            if check_state == "ok" {
                let png = shot_dir.join(format!("{name}.png"));
                let log = shot_dir.join(format!("{name}.log"));
                let _ = fs::remove_file(&png);
                let _ = fs::write(&log, b"");
                let rc = if renderer.name == "pleamar-wm" {
                    render_with_wm(
                        ctx,
                        renderer,
                        name,
                        file,
                        &png,
                        &log,
                        &seconds_text,
                        seconds,
                        hit,
                    )
                } else {
                    render_with_wlroots(
                        ctx,
                        renderer,
                        &pleamar,
                        name,
                        file,
                        &png,
                        &log,
                        &seconds_text,
                        seconds,
                        hit,
                    )
                };
                match verify_png(&png, min_bytes, &min_text) {
                    Ok(size) => {
                        png_size = size;
                        if rc != 0 {
                            render_state = format!("FAIL(exit {rc})");
                            failed = true;
                        } else {
                            render_state = "ok".to_string();
                            rendered_ok += 1;
                        }
                    }
                    Err(reason) => {
                        render_state = "FAIL".to_string();
                        note = format!("{reason} (exit {rc})");
                        failed = true;
                    }
                }
            } else {
                render_state = "skip(check)".to_string();
            }
        } else if check_state == "ok" {
            render_state = "no-renderer".to_string();
        } else {
            render_state = "skip(check)".to_string();
        }

        check_states.push(check_state);
        render_states.push(render_state);
        png_sizes.push(png_size);
        notes.push(note.chars().take(72).collect());
    }

    let mut width = 6usize;
    for name in &names {
        width = width.max(name.chars().count());
    }
    println!();
    println!(
        "{:<width$}  {:<6}  {:<13}  {:<10}  {}",
        "SCENE",
        "CHECK",
        "RENDER",
        "PNG",
        "NOTE",
        width = width
    );
    for index in 0..names.len() {
        println!(
            "{:<width$}  {:<6}  {:<13}  {:<10}  {}",
            names[index],
            check_states[index],
            render_states[index],
            png_sizes[index],
            notes[index],
            width = width
        );
    }
    println!();

    if let Some(renderer) = &renderer {
        ctx.say(format!(
            "renderer: {} ({}); artifacts in {}",
            renderer.name,
            renderer.bin,
            shot_dir.display()
        ));
    } else {
        ctx.say("renderer: none");
    }

    if options.require_render && renderer.is_none() {
        ctx.stderr_bytes(
            format!(
                "smoke: error: --require-render was given but no renderer is available: tried pleamar-wm (PLEAMAR_WM_BIN='{wm_name}') and headless 'sway'/'cage' with 'grim'\n"
            )
            .as_bytes(),
        );
        return Ok(2);
    }
    if failed {
        ctx.say(format!(
            "FAILED: {} scene(s) checked, {rendered_ok} rendered ok",
            names.len()
        ));
        return Ok(1);
    }
    ctx.say(format!(
        "ok: {} scene(s) checked, {rendered_ok} rendered",
        names.len()
    ));
    Ok(0)
}

fn env_or(name: &str, default: &str) -> String {
    match env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

fn setup_env(ctx: &mut Ctx, live: bool) -> Result<(), Halt> {
    let temp = crate::env::mktemp(ctx.tool)?;
    ctx.temp = Some(temp.clone());
    if live {
        ctx.warn("using the ambient environment (--live); rendering stays headless");
        return Ok(());
    }
    if let Err(error) = crate::env::create_sandbox(&temp) {
        return ctx.fail(format!("cannot create the sandbox: {error}"));
    }
    crate::env::enter_sandbox(&temp);
    ctx.say(format!("hermetic environment under {}", temp.display()));
    Ok(())
}

fn detect_renderer(ctx: &Ctx) -> Option<Renderer> {
    let wm_name = env_or("PLEAMAR_WM_BIN", "pleamar-wm");
    let grim = ctx.resolve_bin("grim");
    if let Some(path) = ctx.resolve_bin(&wm_name) {
        return Some(Renderer {
            name: "pleamar-wm".to_string(),
            bin: path,
            grim,
        });
    }
    if grim.is_some() {
        for candidate in ["sway", "cage"] {
            if let Some(path) = ctx.resolve_bin(candidate) {
                return Some(Renderer {
                    name: candidate.to_string(),
                    bin: path,
                    grim: grim.clone(),
                });
            }
        }
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn render_with_wm(
    ctx: &Ctx,
    renderer: &Renderer,
    name: &str,
    file: &Path,
    png: &Path,
    log: &Path,
    seconds_text: &str,
    seconds: u64,
    hit: u64,
) -> i32 {
    let pleamar = env_or("PLEAMAR_BIN", "pleamar");
    let pleamar = ctx.resolve_bin(&pleamar).unwrap_or(pleamar);
    let autostart = ctx.temp().join("autostart");
    let content = format!("{pleamar} --scene {} --no-hud\n", file.display());
    let _ = fs::write(&autostart, content);
    ctx.say(format!(
        "rendering {name} with pleamar-wm headless ({seconds_text}s, shot at {hit}s)"
    ));
    let mut command = Command::new("timeout");
    command
        .arg("-k")
        .arg("5")
        .arg((seconds + 40).to_string())
        .arg(&renderer.bin)
        .arg("headless")
        .arg("--seconds")
        .arg(seconds_text)
        .env("PLEAMAR_WM_AUTOSTART", &autostart)
        .env("PLEAMAR_HEADLESS_AT", hit.to_string())
        .env("PLEAMAR_HEADLESS_PNG", png);
    match proc::status_append(command, log) {
        Ok(status) => proc::exit_code(status),
        Err(_) => 127,
    }
}

#[allow(clippy::too_many_arguments)]
fn render_with_wlroots(
    ctx: &mut Ctx,
    renderer: &Renderer,
    pleamar: &str,
    name: &str,
    file: &Path,
    png: &Path,
    log: &Path,
    seconds_text: &str,
    seconds: u64,
    hit: u64,
) -> i32 {
    let before = ctx.temp().join("sockets.before");
    let after = ctx.temp().join("sockets.after");
    let _ = fs::write(&before, socket_list().join("\n"));
    ctx.say(format!(
        "rendering {name} with headless {} ({seconds_text}s, shot after {hit}s)",
        renderer.name
    ));
    let mut rc = 0i32;
    let comp = (|| -> std::io::Result<u32> {
        let mut command = if renderer.name == "cage" {
            let mut command = Command::new("setsid");
            command
                .arg("timeout")
                .arg("-k")
                .arg("5")
                .arg((seconds + 40).to_string())
                .arg(&renderer.bin)
                .arg("--")
                .arg(pleamar)
                .arg("--scene")
                .arg(file)
                .arg("--no-hud")
                .arg("--seconds")
                .arg(seconds_text);
            command
        } else {
            let mut command = Command::new("setsid");
            command.arg(&renderer.bin).arg("-c").arg("/dev/null");
            command
        };
        command
            .env("WLR_BACKENDS", "headless")
            .env("WLR_HEADLESS_OUTPUTS", "1")
            .env("WLR_LIBINPUT_NO_DEVICES", "1");
        ctx.spawn_log(command, log)
    })();
    let comp = match comp {
        Ok(pid) => Some(pid),
        Err(_) => None,
    };
    let display = wait_for_new_socket(&before, &after);
    let Some(display) = display else {
        ctx.stderr_bytes(
            format!(
                "smoke: {} did not create a Wayland socket; see {}\n",
                renderer.name,
                log.display()
            )
            .as_bytes(),
        );
        return 1;
    };
    let mut scene_pid: Option<u32> = None;
    if renderer.name != "cage" {
        let mut command = Command::new(pleamar);
        command
            .arg("--scene")
            .arg(file)
            .arg("--no-hud")
            .arg("--seconds")
            .arg(seconds_text)
            .env("WAYLAND_DISPLAY", &display);
        match ctx.spawn_log(command, log) {
            Ok(pid) => scene_pid = Some(pid),
            Err(_) => rc = 127,
        }
    }
    if !wait_for_scene_socket(pleamar, name, hit) {
        if let Ok(mut file) = fs::OpenOptions::new().append(true).create(true).open(log) {
            let _ = write!(
                file,
                "smoke: scene {name} did not answer describe within {hit}s\n"
            );
        }
    }
    proc::sleep("1");
    let grim_bin = renderer.grim.as_deref().unwrap_or("grim");
    let mut grim = Command::new("timeout");
    grim.arg("15")
        .arg(grim_bin)
        .arg(png)
        .env("WAYLAND_DISPLAY", &display);
    let _ = proc::status_append(grim, log);

    if renderer.name == "cage" {
        if let Some(pid) = comp {
            if let Some(status) = ctx.wait(pid) {
                rc = proc::exit_code(status);
            } else {
                rc = 127;
            }
        } else {
            rc = 127;
        }
    } else {
        if let Some(pid) = scene_pid {
            if let Some(status) = ctx.wait(pid) {
                rc = proc::exit_code(status);
            } else {
                rc = 127;
            }
        }
        if let Some(pid) = comp {
            ctx.terminate(pid);
        }
    }
    rc
}

fn wait_for_scene_socket(pleamar: &str, name: &str, limit: u64) -> bool {
    let mut step = 0u64;
    while step < limit * 4 {
        let status = Command::new(pleamar)
            .args(["--say", name, "describe"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if status.map(|status| status.success()).unwrap_or(false) {
            return true;
        }
        proc::sleep("0.25");
        step += 1;
    }
    false
}

fn socket_list() -> Vec<String> {
    let root = match env::var("XDG_RUNTIME_DIR") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from("/tmp"),
    };
    let mut names = Vec::new();
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let rest = match name.strip_prefix("wayland-") {
                Some(rest) => rest,
                None => continue,
            };
            if !rest
                .chars()
                .next()
                .map(|character| character.is_ascii_digit())
                .unwrap_or(false)
            {
                continue;
            }
            if fs::metadata(entry.path())
                .map(|metadata| metadata.file_type().is_socket())
                .unwrap_or(false)
            {
                names.push(name);
            }
        }
    }
    names.sort();
    names
}

fn wait_for_new_socket(before: &Path, after: &Path) -> Option<String> {
    let before = fs::read_to_string(before).unwrap_or_default();
    let before: Vec<&str> = before.lines().collect();
    let mut step = 0usize;
    while step < 200 {
        let names = socket_list();
        let mut text = String::new();
        for name in &names {
            text.push_str(name);
            text.push('\n');
        }
        let _ = fs::write(after, &text);
        for name in &names {
            if !before.contains(&name.as_str()) {
                return Some(name.clone());
            }
        }
        proc::sleep("0.1");
        step += 1;
    }
    None
}

fn verify_png(path: &Path, minimum: u64, minimum_text: &str) -> Result<String, String> {
    if !path.is_file() {
        return Err("no PNG written".to_string());
    }
    let size = match text::file_size(path) {
        Some(size) => size,
        None => return Err("no PNG written".to_string()),
    };
    let magic = fs::read(path)
        .ok()
        .map(|bytes| {
            bytes
                .iter()
                .take(8)
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>()
        })
        .unwrap_or_default();
    if size < minimum {
        return Err(format!("PNG too small ({size}B < {minimum_text}B)"));
    }
    if magic != "89504e470d0a1a0a" {
        return Err("not a PNG (bad magic)".to_string());
    }
    Ok(format!("{size}B"))
}
