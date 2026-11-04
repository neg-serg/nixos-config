//! dsh-worktree: git worktrees for parallel dsh sessions (one pane per task).
//!
//! Rust port of `packages/local-bin/bin/dsh-worktree` (POSIX sh). Every
//! worktree gets its own branch (`wt/<name>`) and its own dsh session; trees
//! live outside the repository under `$DSH_WORKTREE_ROOT`, so they never
//! pollute `git status` of the main checkout.

use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{exit, Command, ExitCode, Stdio};

use sha1::{Digest, Sha1};

const USAGE: &str = r#"dsh-worktree: git worktrees for parallel dsh sessions (one pane per task).
Usage:
  dsh-worktree new <name> [--from REF] [--open auto|herdr|kitty|print]
                          [--cmd CMD] [--copy RELPATH]... [--branch BR]
  dsh-worktree list
  dsh-worktree path <name>
  dsh-worktree rm <name> [--force]
  dsh-worktree prune

Every worktree gets its own branch (wt/<name>) and its own dsh session, so
nothing has to be stashed and two agents never fight over the working copy.
Trees live outside the repository, under $DSH_WORKTREE_ROOT, so they never
pollute `git status` of the main checkout.

--open modes: herdr opens the checkout as a Herdr workspace grouped under the
repository (herdr worktree open), kitty a new tab, print just echoes the
command. auto prefers herdr inside a Herdr pane (HERDR_ENV=1), then kitty,
else print.

Env:
  DSH_WORKTREE_ROOT         where trees live (default: ~/.dsh/worktrees)
  DSH_WORKTREE_CMD          command a launched pane runs (default: dsh --profile tui)
  DSH_WORKTREE_POST_CREATE  hook run inside the new worktree after creation
                            (e.g. "ln -s ../../node_modules node_modules")
  HERDR_BIN_PATH            herdr binary for --open herdr (default: herdr on
                            PATH; inside a Herdr pane the server sets it)
"#;

fn die(message: &str) -> ! {
    eprintln!("dsh-worktree: {message}");
    exit(1);
}

fn usage() {
    print!("{USAGE}");
}

fn env_or(name: &str, fallback: &str) -> String {
    env::var(name).unwrap_or_else(|_| fallback.to_string())
}

fn root() -> String {
    env_or("DSH_WORKTREE_ROOT", &format!("{}/.dsh/worktrees", home()))
}

fn home() -> String {
    env::var("HOME").unwrap_or_else(|_| ".".to_string())
}

fn default_cmd() -> String {
    env_or("DSH_WORKTREE_CMD", "dsh --profile tui")
}

fn repo_root() -> String {
    match Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        }
        _ => die("not inside a git repository (run from the repository you want to isolate)"),
    }
}

fn basename(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string())
}

/// One directory per repository, keyed by name + hash of the absolute path so
/// two checkouts with the same basename never collide.
fn repo_slug(top: &str) -> String {
    let mut hasher = Sha1::new();
    hasher.update(top.as_bytes());
    let digest = format!("{:x}", hasher.finalize());
    format!("{}-{}", basename(top), &digest[..8])
}

fn worktree_path(name: &str) -> String {
    let top = repo_root();
    format!("{}/{}/{}", root(), repo_slug(&top), name)
}

fn check_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("empty worktree name".to_string());
    }
    if name.starts_with('-') {
        return Err(format!("worktree name must not start with '-': {name}"));
    }
    if name.contains('/') || name.contains("..") {
        return Err(format!(
            "worktree name must not contain '/' or '..': {name}"
        ));
    }
    if !name
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    {
        return Err(format!(
            "worktree name may only use letters, digits, '.', '_' and '-': {name}"
        ));
    }
    Ok(())
}

fn require_name(name: &str) {
    if let Err(message) = check_name(name) {
        die(&message);
    }
}

fn herdr_bin() -> String {
    env::var("HERDR_BIN_PATH").unwrap_or_else(|_| "herdr".to_string())
}

fn is_executable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn command_exists(bin: &str) -> bool {
    if bin.contains('/') {
        return is_executable(Path::new(bin));
    }
    env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .filter(|dir| !dir.is_empty())
        .any(|dir| is_executable(&Path::new(dir).join(bin)))
}

fn herdr_available() -> bool {
    command_exists(&herdr_bin())
}

fn resolve_open(requested: &str) -> String {
    match requested {
        "auto" => {
            if env::var("HERDR_ENV").as_deref() == Ok("1") && herdr_available() {
                "herdr".to_string()
            } else if !env_or("KITTY_LISTEN_ON", "").is_empty()
                && Command::new("kitty")
                    .arg("@")
                    .arg("ls")
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status()
                    .map(|status| status.success())
                    .unwrap_or(false)
            {
                "kitty".to_string()
            } else {
                "print".to_string()
            }
        }
        "herdr" | "kitty" | "print" => requested.to_string(),
        other => die(&format!(
            "unknown --open mode: {other} (auto|herdr|kitty|print)"
        )),
    }
}

/// The herdr response is JSON; `root_pane.pane_id` names the shell the agent
/// starts in. The shell version scraped it with sed; parse it, and keep a
/// tolerant scan for when herdr prints log lines around the JSON.
fn extract_pane(text: &str) -> Option<String> {
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(text) {
        if let Some(pane) = value
            .get("root_pane")
            .and_then(|pane| pane.get("pane_id"))
            .and_then(serde_json::Value::as_str)
        {
            return Some(pane.to_string());
        }
    }
    let start = text.find("\"root_pane\"")?;
    let rest = &text[start..];
    let pane_at = rest.find("\"pane_id\"")?;
    let after = &rest[pane_at + "\"pane_id\"".len()..];
    let colon = after.find(':')?;
    let tail = &after[colon + 1..];
    let first = tail.find('"')?;
    let value = &tail[first + 1..];
    let second = value.find('"')?;
    Some(value[..second].to_string())
}

fn split_command(cmd: &str) -> Vec<String> {
    cmd.split_whitespace().map(str::to_string).collect()
}

fn output_combined(mut command: Command) -> (bool, String) {
    let output = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();
    match output {
        Ok(output) => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            (output.status.success(), text)
        }
        Err(error) => (false, error.to_string()),
    }
}

fn open_pane(mode: &str, name: &str, path: &str, cmd: &str, top: &str) {
    let mode = resolve_open(mode);
    let label = format!("wt:{name}");
    let parts = split_command(cmd);

    match mode.as_str() {
        "herdr" => {
            let bin = herdr_bin();
            if !herdr_available() {
                die("herdr not found (set HERDR_BIN_PATH or install herdr)");
            }
            let mut open = Command::new(&bin);
            open.args([
                "worktree", "open", "--cwd", top, "--path", path, "--label", &label, "--focus",
            ]);
            let (ok, mut reply) = output_combined(open);
            if !ok {
                let mut create = Command::new(&bin);
                create.args([
                    "workspace",
                    "create",
                    "--cwd",
                    path,
                    "--label",
                    &label,
                    "--focus",
                ]);
                let (ok, reply2) = output_combined(create);
                if !ok {
                    die(&format!("herdr launch failed: {reply2}"));
                }
                reply = reply2;
            }
            let Some(pane) = extract_pane(&reply) else {
                die(&format!("herdr launch failed: {reply}"));
            };
            let status = Command::new(&bin)
                .args(["pane", "run", &pane, cmd])
                .stdout(Stdio::null())
                .status();
            if !matches!(status, Ok(status) if status.success()) {
                die(&format!("herdr pane run failed in {pane}"));
            }
            eprintln!("dsh-worktree: opened a herdr workspace in {path}");
        }
        "kitty" => {
            let mut command = Command::new("kitty");
            command.args([
                "@",
                "launch",
                "--type=tab",
                "--cwd",
                path,
                "--tab-title",
                &label,
                "--",
            ]);
            command.args(&parts);
            let status = command.stdout(Stdio::null()).status();
            if !matches!(status, Ok(status) if status.success()) {
                die("kitty launch failed (is allow_remote_control on?)");
            }
            eprintln!("dsh-worktree: opened a kitty tab in {path}");
        }
        _ => {
            eprintln!("dsh-worktree: cd {path} && {cmd}");
        }
    }
}

fn copy_paths(top: &str, path: &str, copies: &[String]) {
    for rel in copies {
        let src = Path::new(top).join(rel);
        let dst = Path::new(path).join(rel);
        if !src.exists() {
            eprintln!("dsh-worktree: --copy {rel}: not in the main checkout, skipped");
            continue;
        }
        if let Some(parent) = dst.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let status = Command::new("cp").arg("-a").arg(&src).arg(&dst).status();
        if !matches!(status, Ok(status) if status.success()) {
            exit(1);
        }
    }
}

fn take_arg(args: &[String], index: &mut usize, message: &str) -> String {
    *index += 1;
    match args.get(*index) {
        Some(value) => value.clone(),
        None => die(message),
    }
}

fn cmd_new(args: &[String]) -> ExitCode {
    if args.is_empty() {
        die("usage: dsh-worktree new <name> [options]");
    }
    let name = &args[0];
    require_name(name);

    let mut from: Option<String> = None;
    let mut open = "auto".to_string();
    let mut cmd = default_cmd();
    let mut branch: Option<String> = None;
    let mut copies: Vec<String> = Vec::new();
    let mut index = 1;
    while index < args.len() {
        let option = args[index].as_str();
        match option {
            "--from" => from = Some(take_arg(args, &mut index, "--from needs a ref")),
            "--open" => open = take_arg(args, &mut index, "--open needs a mode"),
            "--cmd" => cmd = take_arg(args, &mut index, "--cmd needs a command"),
            "--branch" => branch = Some(take_arg(args, &mut index, "--branch needs a name")),
            "--copy" => copies.push(take_arg(args, &mut index, "--copy needs a path")),
            other => die(&format!("unknown option: {other}")),
        }
        index += 1;
    }

    let top = repo_root();
    let path = worktree_path(name);
    if Path::new(&path).exists() {
        die(&format!(
            "already exists: {path} (use 'dsh-worktree rm {name}' first)"
        ));
    }
    let branch = branch.unwrap_or_else(|| format!("wt/{name}"));
    if Command::new("git")
        .args([
            "show-ref",
            "--verify",
            "--quiet",
            &format!("refs/heads/{branch}"),
        ])
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
    {
        die(&format!(
            "branch '{branch}' already exists (pick another name or --branch)"
        ));
    }
    let from = from.unwrap_or_else(|| {
        let output = Command::new("git")
            .args(["rev-parse", "HEAD"])
            .output()
            .unwrap_or_else(|_| exit(1));
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    });

    if let Some(parent) = Path::new(&path).parent() {
        let _ = fs::create_dir_all(parent);
    }
    eprintln!("dsh-worktree: creating {path} (branch {branch}, from {from})");
    let output = Command::new("git")
        .args(["worktree", "add", "-b", &branch, &path, &from])
        .output()
        .unwrap_or_else(|_| exit(1));
    // The shell redirected git's stdout to stderr; keep both there, in the
    // order git wrote them (progress line on stderr, then the HEAD line).
    if !output.stderr.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
    }
    if !output.stdout.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stdout));
    }
    if !output.status.success() {
        exit(output.status.code().unwrap_or(1));
    }

    copy_paths(&top, &path, &copies);

    if let Ok(hook) = env::var("DSH_WORKTREE_POST_CREATE") {
        if !hook.is_empty() {
            eprintln!("dsh-worktree: post-create hook in {path}");
            let status = Command::new("sh")
                .arg("-c")
                .arg(&hook)
                .current_dir(&path)
                .status();
            if !matches!(status, Ok(status) if status.success()) {
                exit(1);
            }
        }
    }

    open_pane(&open, name, &path, &cmd, &top);
    println!("{path}");
    ExitCode::SUCCESS
}

fn cmd_list() -> ExitCode {
    let top = repo_root();
    let want = format!("{}/{}", root(), repo_slug(&top));
    let output = Command::new("git")
        .args(["worktree", "list", "--porcelain"])
        .stderr(Stdio::null())
        .output();
    let Ok(output) = output else {
        return ExitCode::SUCCESS;
    };
    let mut cur = String::new();
    let mut branch = String::new();
    let text = String::from_utf8_lossy(&output.stdout);
    let flush = |cur: &mut String, branch: &mut String| {
        if !cur.is_empty() && cur.starts_with(&format!("{want}/")) {
            println!(
                "{:<28} {:<28} {}",
                basename(cur),
                branch.strip_prefix("refs/heads/").unwrap_or(branch),
                cur
            );
        }
        cur.clear();
        branch.clear();
    };
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("worktree ") {
            cur = rest.to_string();
        } else if let Some(rest) = line.strip_prefix("branch ") {
            branch = rest.to_string();
        } else if line.is_empty() {
            flush(&mut cur, &mut branch);
        }
    }
    flush(&mut cur, &mut branch);
    ExitCode::SUCCESS
}

fn cmd_path(args: &[String]) -> ExitCode {
    if args.is_empty() {
        die("usage: dsh-worktree path <name>");
    }
    println!("{}", worktree_path(&args[0]));
    ExitCode::SUCCESS
}

fn cmd_rm(args: &[String]) -> ExitCode {
    if args.is_empty() {
        die("usage: dsh-worktree rm <name> [--force]");
    }
    let name = &args[0];
    require_name(name);
    let name_path = worktree_path(name);
    if !Path::new(&name_path).exists() {
        die(&format!("no such worktree: {name}"));
    }
    let force = args.get(1).map(|arg| arg == "--force").unwrap_or(false);
    let mut command = Command::new("git");
    command.args(["worktree", "remove"]);
    if force {
        command.arg("--force");
    }
    command.arg(&name_path);
    let status = command.status().unwrap_or_else(|_| exit(1));
    if !status.success() {
        exit(status.code().unwrap_or(1));
    }
    eprintln!("dsh-worktree: removed {name_path}");
    ExitCode::SUCCESS
}

fn cmd_prune() -> ExitCode {
    let _ = repo_root();
    let status = Command::new("git")
        .args(["worktree", "prune", "-v"])
        .status()
        .unwrap_or_else(|_| exit(1));
    if status.success() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(status.code().unwrap_or(1) as u8)
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        usage();
        return ExitCode::from(2);
    }
    let action = args[0].as_str();
    let rest = &args[1..];
    match action {
        "new" => cmd_new(rest),
        "list" => cmd_list(),
        "path" => cmd_path(rest),
        "rm" => cmd_rm(rest),
        "prune" => cmd_prune(),
        "-h" | "--help" | "help" => {
            usage();
            ExitCode::SUCCESS
        }
        other => die(&format!(
            "unknown command: {other} (new|list|path|rm|prune)"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_validated_like_the_shell() {
        for bad in ["", "-x", "a/b", "a..b", "a b", "a@b"] {
            assert!(check_name(bad).is_err(), "{bad:?} must be refused");
        }
        for good in ["a", "A-Z_0.9", "wt-1"] {
            assert!(check_name(good).is_ok(), "{good:?} must be accepted");
        }
    }

    #[test]
    fn slug_is_name_plus_sha1_prefix() {
        assert_eq!(repo_slug("/tmp/repo"), "repo-d00fead8");
        assert_eq!(repo_slug("/home/neg/src/foo"), "foo-381f16a6");
    }

    #[test]
    fn commands_split_like_shell_word_splitting() {
        assert_eq!(
            split_command("dsh --profile tui"),
            vec!["dsh", "--profile", "tui"]
        );
        assert_eq!(split_command("  a\tb  "), vec!["a", "b"]);
    }

    #[test]
    fn herdr_reply_pane_is_extracted() {
        let reply = r#"{"workspace":{"id":"w"},"root_pane":{"pane_id":"p-42"}}"#;
        assert_eq!(extract_pane(reply).as_deref(), Some("p-42"));
        let noisy = "starting\n{\"root_pane\": {\"pane_id\": \"p-7\"}}\n";
        assert_eq!(extract_pane(noisy).as_deref(), Some("p-7"));
    }

    #[test]
    fn usage_keeps_the_documented_header() {
        assert!(USAGE.contains("dsh-worktree: git worktrees for parallel dsh sessions"));
        assert!(USAGE.contains("DSH_WORKTREE_POST_CREATE"));
    }
}
