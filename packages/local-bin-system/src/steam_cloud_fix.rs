//! steam-cloud-fix: reset Steam Cloud bookkeeping for one app and (re)start
//! the Steam client.
//!
//! Port of `packages/local-bin/bin/steam-cloud-fix` (bash). Only the per-app
//! cloud cache is moved aside — never the cloud account or the saves — so the
//! client rebuilds `remotecache.vdf` and the `ac` staging tree from the server
//! manifest at the next start, which is the only local way out of the
//! "changesincloud" loop.
//!
//! Kept from the original: the Russian operator-facing messages, the argument
//! handling, the env defaults (`STEAM_ROOT`, `BACKUP_ROOT`), the `pgrep`/
//! `pkill`/`timeout`/`date`/`sleep`/`env`/`setsid` argv and the way a failed
//! stop or move aborts the run. The `awk`/`grep`/`sed`/`find` text work is
//! native.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use local_bin_system as sh;

const USAGE: &str = "Reset Steam Cloud bookkeeping for one app and (re)start the Steam client.

Why this exists
---------------
The Steam client keeps a per-app cloud cache (userdata/<id>/<appid>/remotecache.vdf
plus the \"ac\" staging tree). When that cache disagrees with the server manifest,
the client can sit in a \"changesincloud\" loop: it reports saves as needing a
download even when the local file is byte-identical, and only the per-app cache
is ever consulted — restarting the client or verifying game files does not
refresh it. Deleting the two cache paths makes the client rebuild them from the
server manifest at the next start, which is the only local way to break the loop.

Deliberately NOT used: proxychains/LD_PRELOAD routing of Steam through the local
SOCKS5 proxy (features.games.steamProxy). Measured: with the client behind SOCKS5
it stops logging in at all (\"Received logon failure response\" in
logs/steamui_login.txt), so cloud sync cannot work; keep Steam direct.

Nothing here touches the cloud account or the save files themselves: only the
cache is moved aside (backups are kept), never deleted.

Usage:
  steam-cloud-fix                 # repair RimWorld (294100) and start Steam
  steam-cloud-fix --status        # report only, change nothing
  steam-cloud-fix --app 294100 --wait 120
  steam-cloud-fix --no-start      # repair without launching the client

Env: STEAM_ROOT (default ~/.local/share/Steam), BACKUP_ROOT (default
~/.local/share/steam-cloud-fix).
set -euo pipefail

APPID=294100
";

fn fail(message: &str) -> ! {
    sh::err_line(&format!("ошибка: {message}"));
    std::process::exit(1);
}

struct Options {
    appid: String,
    steam_root: String,
    backup_root: String,
    status_only: bool,
    start: bool,
    wait: String,
}

impl Default for Options {
    fn default() -> Options {
        let home = sh::home();
        Options {
            appid: "294100".to_string(),
            steam_root: sh::env_or("STEAM_ROOT", &format!("{home}/.local/share/Steam")),
            backup_root: sh::env_or(
                "BACKUP_ROOT",
                &format!("{home}/.local/share/steam-cloud-fix"),
            ),
            status_only: false,
            start: true,
            wait: "90".to_string(),
        }
    }
}

fn parse(arguments: &[String]) -> Options {
    let mut options = Options::default();
    let mut index = 0;
    while index < arguments.len() {
        match arguments[index].as_str() {
            "--app" => {
                match arguments.get(index + 1) {
                    Some(value) => options.appid = value.clone(),
                    None => fail("--app требует appid"),
                }
                index += 2;
            }
            "--status" => {
                options.status_only = true;
                index += 1;
            }
            "--no-start" => {
                options.start = false;
                index += 1;
            }
            "--wait" => {
                match arguments.get(index + 1) {
                    Some(value) => options.wait = value.clone(),
                    None => fail("--wait требует секунды"),
                }
                index += 2;
            }
            "-h" | "--help" => {
                sh::out_str(USAGE);
                std::process::exit(0);
            }
            other => fail(&format!("неизвестный аргумент: {other}")),
        }
    }
    options
}

/// The numeric userdata entry with the largest id ("0" is the anonymous dir
/// and carries no cloud state).
fn account_dir(steam_root: &str) -> String {
    let mut best: Option<(u128, String)> = None;
    let userdata = Path::new(steam_root).join("userdata");
    if let Ok(entries) = fs::read_dir(&userdata) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            if !name.bytes().all(|byte| byte.is_ascii_digit()) || name.is_empty() {
                continue;
            }
            let Ok(id) = name.parse::<u128>() else {
                continue;
            };
            if id == 0 {
                continue;
            }
            let path_string = path.to_string_lossy().into_owned();
            match &best {
                Some((best_id, _)) if *best_id >= id => {}
                _ => best = Some((id, path_string)),
            }
        }
    }
    best.map(|(_, path)| path).unwrap_or_default()
}

/// `last_sync_state` for the app, as recorded by the client itself.
fn sync_state(account: &str, appid: &str) -> String {
    let path = Path::new(account).join("config/localconfig.vdf");
    let Some(content) = sh::read_text(&path) else {
        return String::new();
    };
    let app_marker = format!("\"{appid}\"");
    let mut inside = false;
    for line in content.split('\n') {
        if line.ends_with(&app_marker) {
            inside = true;
        }
        if inside && line.contains("last_sync_state") {
            let cleaned: String = line
                .chars()
                .filter(|character| !matches!(character, '"' | '\t' | ' '))
                .collect();
            return cleaned
                .strip_prefix("last_sync_state")
                .unwrap_or(&cleaned)
                .to_string();
        }
        if inside && line.starts_with("\t\t\t\t\t}") {
            inside = false;
        }
    }
    String::new()
}

fn is_ascii_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\u{000b}' | '\u{000c}' | '\r')
}

/// Recent cloud_log lines for the app, already rewritten to
/// `<time>  <rest>` and clipped to 140 characters.
fn recent_log(steam_root: &str, appid: &str, limit: usize) -> Vec<String> {
    let path = Path::new(steam_root).join("logs/cloud_log.txt");
    let Some(content) = sh::read_text(&path) else {
        return Vec::new();
    };
    let marker = format!("[AppID {appid}]");
    let mut lines: Vec<String> = content
        .split('\n')
        .filter(|line| line.contains(&marker))
        .filter(|line| !line.chars().all(is_ascii_space))
        .map(str::to_string)
        .collect();
    if lines.len() > limit {
        lines.drain(0..lines.len() - limit);
    }
    lines
        .into_iter()
        .map(|line| clip_chars(&rewrite_log_line(&line), 140))
        .collect()
}

/// `sed -E 's/^\[[0-9-]+ ([0-9:]+)\] \[AppID [0-9]+\] /\1  /'`.
fn rewrite_log_line(line: &str) -> String {
    let bytes = line.as_bytes();
    if bytes.first() != Some(&b'[') {
        return line.to_string();
    }
    let mut index = 1;
    while index < bytes.len() && (bytes[index].is_ascii_digit() || bytes[index] == b'-') {
        index += 1;
    }
    if index == 1 || index >= bytes.len() || bytes[index] != b' ' {
        return line.to_string();
    }
    index += 1;
    let capture_start = index;
    while index < bytes.len() && (bytes[index].is_ascii_digit() || bytes[index] == b':') {
        index += 1;
    }
    if index == capture_start || index >= bytes.len() || bytes[index] != b']' {
        return line.to_string();
    }
    let capture = &line[capture_start..index];
    index += 1;
    let rest = &line[index..];
    let Some(rest) = rest.strip_prefix(" [AppID ") else {
        return line.to_string();
    };
    let digits = rest
        .bytes()
        .take_while(|byte| byte.is_ascii_digit())
        .count();
    if digits == 0 {
        return line.to_string();
    }
    let rest = &rest[digits..];
    let Some(rest) = rest.strip_prefix("] ") else {
        return line.to_string();
    };
    format!("{capture}  {rest}")
}

fn clip_chars(text: &str, limit: usize) -> String {
    text.chars().take(limit).collect()
}

/// Count regular files at depth 0..=2 under the app directory (the original
/// `find -maxdepth 2 -type f | wc -l`).
fn count_files(root: &Path) -> usize {
    fn walk(directory: &Path, remaining: usize, count: &mut usize) {
        let Ok(entries) = fs::read_dir(directory) else {
            return;
        };
        for entry in entries.flatten() {
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_file() {
                *count += 1;
            } else if file_type.is_dir() && remaining > 1 {
                walk(&entry.path(), remaining - 1, count);
            }
        }
    }
    let mut count = 0;
    walk(root, 2, &mut count);
    count
}

fn state_text(state: &str) -> &str {
    match state {
        "synchronized" => "синхронизировано",
        "changesincloud" => "в облаке есть изменения, которых нет локально (ждёт загрузки)",
        "changeslocal" => "локальные изменения ждут выгрузки",
        "" => "состояние не записано клиентом",
        other => other,
    }
}

fn report(options: &Options, account: &str) {
    let appdir = PathBuf::from(format!("{account}/{}", options.appid));
    let state = sync_state(account, &options.appid);
    sh::out_str_line(&format!(
        "RimWorld (appid {}), профиль {}",
        options.appid,
        sh::basename(account)
    ));
    sh::out_str_line(&format!("  состояние облака: {}", state_text(&state)));

    let appdir_text = appdir.to_string_lossy().into_owned();
    if appdir.is_dir() {
        let files = count_files(&appdir);
        sh::out_str_line(&format!(
            "  кэш облака: {} ({} файлов)",
            sh::strip_prefix_with_slash(&appdir_text, &options.steam_root),
            files
        ));
    } else {
        sh::out_str_line("  кэш облака: нет (клиент ещё не заводил его для этой игры)");
    }

    let cloud_log = Path::new(&options.steam_root).join("logs/cloud_log.txt");
    if cloud_log.is_file() {
        sh::out_str_line(&format!(
            "  последние строки {}:",
            sh::strip_prefix_with_slash(&cloud_log.to_string_lossy(), &options.steam_root)
        ));
        for line in recent_log(&options.steam_root, &options.appid, 8) {
            sh::out_str_line(&format!("    {line}"));
        }
    }
}

fn steam_running() -> bool {
    Command::new("pgrep")
        .args(["-f", "steamrt64/steam"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// `sleep N` with `set -e` semantics: a missing `sleep` is 127, a failing one
/// aborts with its own status.
fn sleep_required(argument: &str) {
    match Command::new("sleep").arg(argument).status() {
        Ok(status) if status.success() => {}
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}

fn stop_steam() {
    sh::out_str_line("останавливаю Steam...");
    if sh::which("steam").is_some() {
        let _ = Command::new("timeout")
            .args(["60", "steam", "-shutdown"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    for _ in 0..30 {
        if !steam_running() {
            break;
        }
        sleep_required("1");
    }
    if steam_running() {
        let _ = Command::new("pkill")
            .args(["-TERM", "-f", "steamrt64/steam"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        for _ in 0..20 {
            if !steam_running() {
                break;
            }
            sleep_required("1");
        }
    }
    if steam_running() {
        fail("Steam не завершился — закрой его вручную и повтори");
    }
}

fn move_one(source: &Path, destination: &str) -> bool {
    if !source.exists() {
        return true;
    }
    let target = format!("{destination}/");
    match Command::new("mv")
        .args([source.as_os_str(), target.as_ref()])
        .status()
    {
        Ok(status) if status.success() => true,
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}

fn run(options: &Options) {
    if !Path::new(&options.steam_root).is_dir() {
        fail(&format!("нет каталога Steam: {}", options.steam_root));
    }
    let account = account_dir(&options.steam_root);
    if account.is_empty() {
        fail(&format!(
            "не найден профиль в {}/userdata",
            options.steam_root
        ));
    }

    if options.status_only {
        report(options, &account);
        return;
    }

    if steam_running() {
        stop_steam();
    }

    // Move the per-app cloud cache aside; the client rebuilds it from the
    // server manifest at the next start.
    let stamp = match Command::new("date").arg("+%Y%m%d-%H%M%S").output() {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .trim_end_matches('\n')
            .to_string(),
        Ok(output) => std::process::exit(sh::status_code(output.status)),
        Err(_) => std::process::exit(127),
    };
    let destination = format!("{}/{}-{}", options.backup_root, options.appid, stamp);
    let appdir = format!("{account}/{}", options.appid);
    let remote_cache = Path::new(&appdir).join("remotecache.vdf");
    let staging = Path::new(&appdir).join("ac");
    if remote_cache.exists() || staging.exists() {
        if let Err(error) = fs::create_dir_all(&destination) {
            sh::err_line(&format!(
                "mkdir: cannot create directory '{destination}': {error}"
            ));
            std::process::exit(1);
        }
        move_one(&remote_cache, &destination);
        move_one(&staging, &destination);
        sh::out_str_line(&format!("кэш облака убран в {destination}"));
    } else {
        sh::out_str_line("кэш облака уже пуст — нечего убирать");
    }

    if !options.start {
        sh::out_str_line("Steam не запускаю (--no-start).");
        return;
    }

    // Launch the client the way the desktop session does: detached, direct
    // connection (no proxy env), inheriting DISPLAY/WAYLAND_DISPLAY/XDG_RUNTIME_DIR.
    let steam_bin = match sh::which("steam") {
        Some(path) => path.to_string_lossy().into_owned(),
        None => format!("{}/steam.sh", options.steam_root),
    };
    if !sh::is_executable(Path::new(&steam_bin)) {
        fail(&format!("не нашёл steam ({steam_bin})"));
    }
    let _ = Command::new("env")
        .args([
            "-u",
            "ALL_PROXY",
            "-u",
            "all_proxy",
            "-u",
            "http_proxy",
            "-u",
            "https_proxy",
            "-u",
            "HTTP_PROXY",
            "-u",
            "HTTPS_PROXY",
            "setsid",
            &steam_bin,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .stdin(Stdio::null())
        .spawn();
    sh::out_str_line(&format!(
        "Steam запускается, жду {} с и смотрю облако...",
        options.wait
    ));
    sleep_required(&options.wait);

    report(options, &account);
    sh::out_str_line(
        "\nЕсли по-прежнему \"Download Timeout\" с хоста steamcloud-*.s3.dualstack.*:",
    );
    sh::out_str_line("  это ответ на стороне CDN Valve, а не локальная поломка — повтори позже");
    sh::out_str_line(
        "  или запусти игру, чтобы клиент разрешил конфликт сохранений своей стороной.",
    );
}

fn main() {
    let arguments = sh::args();
    let options = parse(&arguments);
    run(&options);
    // The report path and the repair path both end here with status 0; flush
    // explicitly so a detached child cannot swallow buffered output.
    let _ = std::io::stdout().flush();
}
