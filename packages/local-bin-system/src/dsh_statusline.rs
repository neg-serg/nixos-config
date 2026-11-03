//! dsh-statusline: one status line for a dsh session.
//!
//! Port of `packages/local-bin/bin/dsh-statusline` (POSIX sh). The protocol is
//! the contract: session JSON on stdin, exactly one line on stdout. Every field
//! is optional and a missing field degrades instead of failing, because a host
//! calls this every few seconds with a short timeout.
//!
//! Kept from the original: `git` is still a subprocess with the same argv
//! (`git -C DIR rev-parse …`, `git -C DIR status --porcelain=v1`), the glyphs,
//! the `DSH_STATUSLINE_PARTS` filter, the worktree naming and the two non-
//! protocol modes. JSON parsing is native (the original shelled out to `jq`).

use std::path::Path;

use local_bin_system as sh;
use serde_json::Value;

const SEP: &str = " · ";

const USAGE: &str = "dsh-statusline: one status line for a dsh session.

Protocol mode (what a status-line host calls): the session state arrives as
JSON on stdin and the FIRST LINE of stdout is the status line. The payload is
the Claude-Code-compatible subset:

  { \"session_id\": \"...\", \"turn\": 7,
    \"model\": { \"display_name\": \"deepseek-v4\" },
    \"workspace\": { \"current_dir\": \"/path/to/repo\" },
    \"git\": { \"branch\": \"main\" },
    \"context\": { \"ratio\": 0.42, \"estimated_tokens\": 54000, \"max_tokens\": 128000 },
    \"cost\": { \"total_yuan\": 0.12 } }

Every field is optional; missing data is simply left out of the line. The
script is deliberately fast and local (one `git status`), because a host may
call it every few seconds with a ~2s timeout.

Modes:
  dsh-statusline                 protocol mode (JSON on stdin)
  dsh-statusline --git [DIR]     only the git/worktree segment (for a prompt
                                 or `kitty @ set-tab-title`)
  dsh-statusline --demo          run protocol mode against a canned payload
  dsh-statusline --help

Env:
  DSH_STATUSLINE_PARTS   comma list to limit segments:
                         place,state,context,turn,cost (default: all)

set -eu
";

fn usage() {
    sh::out_str(USAGE);
}

/// `$PWD`: shells keep the logical path, so prefer the inherited variable and
/// only fall back to the process directory.
fn pwd() -> String {
    match sh::env_nonempty("PWD") {
        Some(value) => value,
        None => std::env::current_dir()
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_default(),
    }
}

fn want_part(name: &str) -> bool {
    let parts = format!(
        ",{},",
        sh::env_or("DSH_STATUSLINE_PARTS", "place,state,context,turn,cost")
    );
    parts.contains(&format!(",{name},"))
}

/// A dsh worktree lives at `$DSH_WORKTREE_ROOT/<repo>-<hash>/<name>` and is
/// named by its last component; anything else falls through to the branch.
fn worktree_name(directory: &str) -> String {
    let root = sh::env_or(
        "DSH_WORKTREE_ROOT",
        &format!("{}/.dsh/worktrees", sh::home()),
    );
    let prefix = format!("{root}/");
    match directory.strip_prefix(&prefix) {
        Some(rest) => rest.rsplit('/').next().unwrap_or("").to_string(),
        None => String::new(),
    }
}

fn git_capture(directory: &str, arguments: &[&str], stderr_null: bool) -> Option<String> {
    let mut full = vec!["-C", directory];
    full.extend_from_slice(arguments);
    sh::capture_text("git", &full, stderr_null)
}

/// `git … rev-parse --is-inside-work-tree >/dev/null 2>&1`: only the exit
/// status matters (the original discards the `true` it prints).
fn inside_work_tree(directory: &str) -> bool {
    let mut full = vec!["-C", directory];
    full.extend_from_slice(&["rev-parse", "--is-inside-work-tree"]);
    sh::capture("git", &full, true)
        .map(|output| output.status.success())
        .unwrap_or(false)
}

/// "3 staged, 2 modified, 1 untracked" → compact glyphs, empty when clean.
fn dirty_summary(directory: &str) -> String {
    if sh::which("git").is_none() {
        return String::new();
    }
    if !inside_work_tree(directory) {
        return String::new();
    }
    let status = match git_capture(directory, &["status", "--porcelain=v1"], true) {
        Some(text) => text,
        None => return String::new(),
    };
    if status.is_empty() {
        return String::new();
    }
    let mut staged = 0usize;
    let mut modified = 0usize;
    let mut untracked = 0usize;
    for line in status.split('\n') {
        if line.is_empty() {
            continue;
        }
        if line.starts_with("??") {
            untracked += 1;
            continue;
        }
        let first = line.chars().next().map(String::from).unwrap_or_default();
        let second = line.chars().nth(1).map(String::from).unwrap_or_default();
        if first != " " && first != "?" {
            staged += 1;
        }
        if second != " " && second != "?" {
            modified += 1;
        }
    }
    let mut summary = String::new();
    if staged > 0 {
        summary.push_str(&format!(" ◆{staged}"));
    }
    if modified > 0 {
        summary.push_str(&format!(" ✚{modified}"));
    }
    if untracked > 0 {
        summary.push_str(&format!(" ?{untracked}"));
    }
    summary
}

fn place_segment(directory: &str) -> String {
    let worktree = worktree_name(directory);
    if !worktree.is_empty() {
        return format!("wt:{worktree}");
    }
    let branch =
        git_capture(directory, &["rev-parse", "--abbrev-ref", "HEAD"], true).unwrap_or_default();
    if !branch.is_empty() && branch != "HEAD" {
        return format!("⎇ {branch}");
    }
    String::new()
}

fn git_only(arguments: &[String]) {
    let mut directory = arguments
        .first()
        .filter(|value| !value.is_empty())
        .cloned()
        .unwrap_or_else(pwd);
    if !Path::new(&directory).is_dir() {
        directory = pwd();
    }
    let mut place = place_segment(&directory);
    let state = dirty_summary(&directory);
    if place.is_empty() {
        place = sh::basename(&directory);
    }
    sh::out_str_line(&format!("{place}{state}"));
}

/// The subset of the payload the line renders. A malformed document behaves
/// like the original's failing `jq` calls: every field is simply absent.
#[derive(Default)]
struct Payload {
    directory: Option<String>,
    turn: Option<String>,
    ratio: Option<String>,
    tokens: Option<String>,
    max_tokens: Option<String>,
    cost: Option<String>,
}

fn dig<'a>(root: &'a Value, path: &[&str]) -> Option<&'a Value> {
    let mut current = root;
    for key in path {
        current = current.as_object()?.get(*key)?;
    }
    Some(current)
}

impl Payload {
    fn from_stdin() -> Payload {
        let mut input = String::new();
        use std::io::Read;
        if std::io::stdin().read_to_string(&mut input).is_err() {
            return Payload::default();
        }
        let value: Value = match serde_json::from_str(&input) {
            Ok(value) => value,
            Err(_) => return Payload::default(),
        };
        Payload {
            directory: dig(&value, &["workspace", "current_dir"]).and_then(sh::jq_alt_empty),
            turn: dig(&value, &["turn"]).and_then(sh::jq_alt_empty),
            ratio: dig(&value, &["context", "ratio"]).and_then(sh::jq_alt_empty),
            tokens: dig(&value, &["context", "estimated_tokens"]).and_then(sh::jq_alt_empty),
            max_tokens: dig(&value, &["context", "max_tokens"]).and_then(sh::jq_alt_empty),
            cost: dig(&value, &["cost", "total_yuan"]).and_then(sh::jq_alt_empty),
        }
    }
}

fn protocol(payload: Payload) {
    let directory = payload
        .directory
        .filter(|value| !value.is_empty())
        .unwrap_or_else(pwd);

    let mut line = String::new();
    let mut append = |part: &str| {
        if !line.is_empty() {
            line.push_str(SEP);
        }
        line.push_str(part);
    };

    if want_part("place") || want_part("state") {
        let mut place = place_segment(&directory);
        if place.is_empty() {
            place = sh::basename(&directory);
        }
        if want_part("place") {
            append(&place);
        }
        if want_part("state") {
            let state = dirty_summary(&directory);
            if !state.is_empty() {
                append(state.trim_start_matches(' '));
            }
        }
    }

    if want_part("context") {
        if let Some(ratio) = payload.ratio.as_deref().filter(|value| *value != "null") {
            let percent = (sh::awk_number(ratio) * 100.0 + 0.5) as i64;
            append(&format!("ctx {percent}%"));
        } else if let (Some(tokens), Some(max_tokens)) = (
            payload.tokens.as_deref(),
            payload
                .max_tokens
                .as_deref()
                .filter(|value| *value != "null"),
        ) {
            let maximum = sh::awk_number(max_tokens);
            if maximum == 0.0 {
                append("ctx ");
            } else {
                let percent = (sh::awk_number(tokens) / maximum * 100.0 + 0.5) as i64;
                append(&format!("ctx {percent}%"));
            }
        } else if let Some(tokens) = payload.tokens.as_deref() {
            let thousands = (sh::awk_number(tokens) / 1000.0) as i64;
            append(&format!("{thousands}k tok"));
        }
    }

    if want_part("turn") {
        if let Some(turn) = payload.turn.as_deref().filter(|value| *value != "-1") {
            append(&format!("turn {turn}"));
        }
    }

    if want_part("cost") {
        if let Some(cost) = payload.cost.as_deref().filter(|value| *value != "null") {
            let value = sh::awk_number(cost);
            if value > 0.0 {
                append(&format!("¥{value:.3}"));
            }
        }
    }

    if line.is_empty() {
        line = "dsh".to_string();
    }
    sh::out_str_line(&line);
}

fn demo() {
    let directory = pwd();
    let document = format!(
        "{{\"session_id\":\"demo\",\"turn\":7,\"model\":{{\"display_name\":\"deepseek-v4\"}},\
         \"workspace\":{{\"current_dir\":\"{directory}\"}},\"context\":{{\"ratio\":0.42}},\
         \"cost\":{{\"total_yuan\":0.1234}}}}"
    );
    let value: Value = serde_json::from_str(&document).unwrap_or(Value::Null);
    let payload = Payload {
        directory: dig(&value, &["workspace", "current_dir"]).and_then(sh::jq_alt_empty),
        turn: dig(&value, &["turn"]).and_then(sh::jq_alt_empty),
        ratio: dig(&value, &["context", "ratio"]).and_then(sh::jq_alt_empty),
        tokens: dig(&value, &["context", "estimated_tokens"]).and_then(sh::jq_alt_empty),
        max_tokens: dig(&value, &["context", "max_tokens"]).and_then(sh::jq_alt_empty),
        cost: dig(&value, &["cost", "total_yuan"]).and_then(sh::jq_alt_empty),
    };
    protocol(payload);
}

fn main() {
    let arguments = sh::args();
    let first = arguments.first().map(String::as_str).unwrap_or("");
    match first {
        "" | "--stdin" => protocol(Payload::from_stdin()),
        "--git" => git_only(&arguments[1..]),
        "--demo" => demo(),
        "-h" | "--help" | "help" => usage(),
        other => {
            sh::err_line(&format!(
                "dsh-statusline: unknown option '{other}' (use --git, --demo, --help)"
            ));
            std::process::exit(2);
        }
    }
}
