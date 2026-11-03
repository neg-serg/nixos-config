//! Rust port of `packages/local-bin/bin/gh-issues-export`.
//!
//! Fetches a repository's issues and comments through `gh api`, filters out
//! pull requests and writes one Markdown file per issue with the original YAML
//! frontmatter and comment sections. The incremental `.export-meta.json`
//! timestamp round-trips exactly like the shell version.
//!
//! `gh` is still spawned with the original argv. The shell also piped its
//! output through `jq` and used `jq`, `sed`, `date` and shell arithmetic for
//! everything else; that shaping is native here, which is why `jq` is no
//! longer a dependency of this command (the original exited 2 without it).
//! JSON is parsed with serde_json: the paginated stream may contain several
//! concatenated pages, exactly what `gh api --paginate` prints.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use local_bin_zsh_extra::{
    capture_checked, err_line, err_str, out_line, out_str, raw_args, report_spawn_failure, run,
    which_str, Captured, StdioMode,
};

const USAGE: &str = include_str!("gh_issues_export_usage.txt");

struct Options {
    output_dir: Option<String>,
    state: String,
    full: bool,
    repository: String,
}

fn main() {
    let options = parse_args();
    let slug = normalize_repo(options.repository);
    check_deps();
    validate_repo(&slug);

    let output_dir = options
        .output_dir
        .unwrap_or_else(|| format!("./gh-issues/{}", slug.replace('/', "-")));
    match run(
        "mkdir",
        &[OsString::from("-p"), OsString::from(&output_dir)],
        StdioMode::Inherit,
        StdioMode::Inherit,
    ) {
        Ok(_) => {}
        Err(error) => {
            report_spawn_failure("gh-issues-export", "mkdir", &error, StdioMode::Inherit);
        }
    }

    let since = if options.full {
        out_line("Full export mode (--full)");
        String::new()
    } else {
        let since = read_export_meta(&output_dir);
        if !since.is_empty() {
            out_line(&format!(
                "Incremental export: fetching issues updated since {since}"
            ));
        }
        since
    };

    out_line(&format!(
        "Fetching issues from {slug} (state={})...",
        options.state
    ));
    let issues = match fetch_issues(&slug, &options.state, &since) {
        Ok(issues) => issues,
        Err(()) => {
            err_line(&format!("error: failed to fetch issues from {slug}"));
            std::process::exit(4);
        }
    };

    if issues.is_empty() {
        out_line("No issues found.");
        write_export_meta(&output_dir, &slug, 0);
        return;
    }

    let total = issues.len();
    out_line(&format!("Found {total} issues. Exporting..."));

    let mut failed = 0usize;
    for (index, issue) in issues.iter().enumerate() {
        let number = raw_field(issue.get("number"));
        let title = raw_field(issue.get("title"));
        out_line(&format!(
            "[{}/{}] Exporting issue #{number}: {title}",
            index + 1,
            total
        ));
        if !export_issue(issue, Path::new(&output_dir), &slug) {
            err_line(&format!(
                "  warning: failed to export issue #{number}, skipping"
            ));
            failed += 1;
        }
    }

    write_export_meta(&output_dir, &slug, total);

    out_line("");
    out_line(&format!(
        "Export complete: {}/{} issues exported to {output_dir}",
        total - failed,
        total
    ));
    if failed > 0 {
        out_line(&format!("  ({failed} issues failed — re-run to retry)"));
        // The shell's last command is `(( failed > 0 )) && print ...`; when
        // nothing failed the arithmetic test returns 1 and that becomes the
        // script's exit status. The port preserves that observable quirk.
        return;
    }
    std::process::exit(1);
}

fn parse_args() -> Options {
    let mut arguments = raw_args().into_iter();
    let mut output_dir = None;
    let mut state = "all".to_string();
    let mut full = false;
    let mut repository = None;

    while let Some(argument) = arguments.next() {
        let text = argument.to_string_lossy().into_owned();
        match text.as_str() {
            "--output" => match arguments.next() {
                Some(value) if !value.is_empty() => {
                    output_dir = Some(value.to_string_lossy().into_owned());
                }
                _ => {
                    err_line("error: --output requires a directory argument");
                    std::process::exit(1);
                }
            },
            "--state" => match arguments.next() {
                Some(value) if !value.is_empty() => {
                    let value = value.to_string_lossy().into_owned();
                    match value.as_str() {
                        "open" | "closed" | "all" => state = value,
                        _ => {
                            err_line("error: --state must be open, closed, or all");
                            std::process::exit(1);
                        }
                    }
                }
                _ => {
                    err_line("error: --state requires open|closed|all");
                    std::process::exit(1);
                }
            },
            "--full" => full = true,
            "--help" | "-h" => {
                out_str(USAGE);
                std::process::exit(0);
            }
            other if other.starts_with('-') => {
                err_line(&format!("error: unknown option {other}"));
                err_str(USAGE);
                std::process::exit(1);
            }
            other => {
                if repository.is_some() {
                    err_line(&format!("error: unexpected argument '{other}'"));
                    std::process::exit(1);
                }
                repository = Some(other.to_string());
            }
        }
    }

    let Some(repository) = repository else {
        err_line("error: repository argument required");
        err_str(USAGE);
        std::process::exit(1);
    };

    Options {
        output_dir,
        state,
        full,
        repository,
    }
}

fn normalize_repo(mut slug: String) -> String {
    for prefix in ["https://github.com/", "http://github.com/"] {
        if let Some(rest) = slug.strip_prefix(prefix) {
            slug = rest.to_string();
        }
    }
    if let Some(rest) = slug.strip_suffix(".git") {
        slug = rest.to_string();
    }
    if let Some(rest) = slug.strip_suffix('/') {
        slug = rest.to_string();
    }
    if !valid_repository(&slug) {
        err_line(&format!(
            "error: invalid repository format '{slug}' (expected owner/repo)"
        ));
        std::process::exit(1);
    }
    slug
}

fn valid_repository(slug: &str) -> bool {
    let Some((owner, repository)) = slug.split_once('/') else {
        return false;
    };
    !owner.is_empty()
        && !repository.is_empty()
        && !repository.contains('/')
        && owner.chars().chain(repository.chars()).all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-')
        })
}

fn check_deps() {
    if which_str("gh").is_none() {
        err_line("error: gh CLI not found (add to environment.systemPackages: pkgs.gh)");
        std::process::exit(2);
    }
    let status = run(
        "gh",
        &[OsString::from("auth"), OsString::from("token")],
        StdioMode::Null,
        StdioMode::Null,
    )
    .unwrap_or(127);
    if status != 0 {
        err_line("error: gh CLI not authenticated (run: gh auth login)");
        std::process::exit(2);
    }
}

fn validate_repo(slug: &str) {
    let status = run(
        "gh",
        &[
            OsString::from("api"),
            OsString::from(format!("repos/{slug}")),
            OsString::from("--silent"),
        ],
        StdioMode::Null,
        StdioMode::Null,
    )
    .unwrap_or(127);
    if status != 0 {
        err_line(&format!(
            "error: repository '{slug}' not found or access denied"
        ));
        std::process::exit(3);
    }
}

fn gh_capture(arguments: &[&str]) -> Option<Captured> {
    let arguments: Vec<OsString> = arguments.iter().map(OsString::from).collect();
    capture_checked("gh", "gh", &arguments, StdioMode::Null)
}

fn parse_json_stream(bytes: &[u8]) -> Result<Vec<Value>, ()> {
    let mut values = Vec::new();
    for value in serde_json::Deserializer::from_slice(bytes).into_iter::<Value>() {
        values.push(value.map_err(|_| ())?);
    }
    Ok(values)
}

fn fetch_issues(slug: &str, state: &str, since: &str) -> Result<Vec<Value>, ()> {
    let since_parameter = if since.is_empty() {
        String::new()
    } else {
        format!("&since={since}")
    };
    let url = format!(
        "/repos/{slug}/issues?state={state}&per_page=100&sort=created&direction=asc{since_parameter}"
    );
    let captured = gh_capture(&["api", "--paginate", &url]).ok_or(())?;
    if captured.status != 0 {
        return Err(());
    }
    let mut issues = Vec::new();
    for page in parse_json_stream(&captured.stdout)? {
        let page = page.as_array().ok_or(())?;
        for issue in page {
            let is_pull_request = match issue.get("pull_request") {
                None => false,
                Some(value) => !value.is_null(),
            };
            if !is_pull_request {
                issues.push(issue.clone());
            }
        }
    }
    Ok(issues)
}

fn fetch_comments(slug: &str, number: &str) -> Result<Vec<Value>, ()> {
    let url = format!("/repos/{slug}/issues/{number}/comments?per_page=100");
    let captured = gh_capture(&["api", "--paginate", &url]).ok_or(())?;
    if captured.status != 0 {
        return Err(());
    }
    let mut comments = Vec::new();
    for page in parse_json_stream(&captured.stdout)? {
        let page = page.as_array().ok_or(())?;
        comments.extend(page.iter().cloned());
    }
    Ok(comments)
}

fn export_issue(issue: &Value, target_dir: &Path, slug: &str) -> bool {
    let number = raw_field(issue.get("number"));
    let outfile = target_dir.join(format!("{number}.md"));
    // The shell opens the group's redirection before running any of the body,
    // so a failed open skips the rate-limit/comments work entirely.
    let mut file = match fs::File::create(&outfile) {
        Ok(file) => file,
        Err(error) => {
            redirection_failure("export_issue", 12, &outfile, &error);
            return false;
        }
    };

    let mut content = frontmatter(issue);
    content.push('\n');
    content.push_str(&issue_body(issue));
    content.push('\n');

    let comment_count = issue.get("comments").and_then(Value::as_i64).unwrap_or(0);
    if comment_count > 0 {
        if let Some(line) = check_rate_limit() {
            content.push_str(&line);
            content.push('\n');
        }
        match fetch_comments(slug, &number) {
            Ok(comments) => content.push_str(&format_comments(&comments)),
            Err(()) => {
                err_line(&format!(
                    "  warning: failed to fetch comments for issue #{number}"
                ));
            }
        }
    }

    match file.write_all(content.as_bytes()) {
        Ok(()) => true,
        Err(error) => {
            redirection_failure("export_issue", 12, &outfile, &error);
            false
        }
    }
}

/// zsh's redirection diagnostic: `<function>:<line>: <strerror>: <path>`.
fn redirection_failure(function: &str, line: u32, path: &Path, error: &std::io::Error) {
    let text = error.to_string();
    let text = match text.find(" (os error ") {
        Some(position) => text[..position].to_string(),
        None => text,
    };
    let mut characters = text.chars();
    let message = match characters.next() {
        Some(first) => first.to_lowercase().collect::<String>() + characters.as_str(),
        None => String::new(),
    };
    err_line(&format!("{function}:{line}: {message}: {}", path.display()));
}

fn frontmatter(issue: &Value) -> String {
    let mut text = String::from("---\n");
    text.push_str(&format!("number: {}\n", raw_field(issue.get("number"))));
    text.push_str(&format!("title: {}\n", json_field(issue.get("title"))));
    text.push_str(&format!("state: {}\n", raw_field(issue.get("state"))));
    text.push_str(&format!(
        "author: {}\n",
        raw_field(issue.get("user").and_then(|user| user.get("login")))
    ));

    let labels: Vec<String> = issue
        .get("labels")
        .and_then(Value::as_array)
        .map(|labels| {
            labels
                .iter()
                .map(|label| json_field(label.get("name")))
                .collect()
        })
        .unwrap_or_default();
    text.push_str(&format!("labels: [{}]\n", labels.join(", ")));

    let assignees: Vec<String> = issue
        .get("assignees")
        .and_then(Value::as_array)
        .map(|assignees| {
            assignees
                .iter()
                .map(|assignee| json_field(assignee.get("login")))
                .collect()
        })
        .unwrap_or_default();
    text.push_str(&format!("assignees: [{}]\n", assignees.join(", ")));

    if truthy(issue.get("milestone")) {
        text.push_str(&format!(
            "milestone: {}\n",
            json_field(
                issue
                    .get("milestone")
                    .and_then(|milestone| milestone.get("title"))
            )
        ));
    }
    text.push_str(&format!(
        "created_at: \"{}\"\n",
        raw_field(issue.get("created_at"))
    ));
    text.push_str(&format!(
        "updated_at: \"{}\"\n",
        raw_field(issue.get("updated_at"))
    ));
    if truthy(issue.get("closed_at")) {
        text.push_str(&format!(
            "closed_at: \"{}\"\n",
            raw_field(issue.get("closed_at"))
        ));
    }
    text.push_str(&format!("url: \"{}\"\n", raw_field(issue.get("html_url"))));
    text.push_str(&format!(
        "comments_count: {}\n",
        raw_field(issue.get("comments"))
    ));
    text.push_str("---\n");
    text
}

fn format_comments(comments: &[Value]) -> String {
    let mut text = String::new();
    for comment in comments {
        let author = raw_field(comment.get("user").and_then(|user| user.get("login")));
        let created_at = raw_field(comment.get("created_at"));
        let body = match comment.get("body") {
            Some(Value::Null) | None => String::new(),
            Some(Value::Bool(false)) => String::new(),
            Some(Value::String(body)) => body.clone(),
            Some(other) => other.to_string(),
        };
        text.push('\n');
        text.push_str(&format!("## Comment by {author} on {created_at}\n"));
        text.push('\n');
        text.push_str(&body);
        text.push('\n');
    }
    text
}

fn issue_body(issue: &Value) -> String {
    match issue.get("body") {
        Some(Value::Null) | None => String::new(),
        Some(Value::Bool(false)) => String::new(),
        Some(Value::String(body)) => strip_html_comments(body),
        Some(other) => other.to_string(),
    }
}

/// sed's `s/<!--.*-->//g` per line: the `.*` is greedy, so a line with two
/// comments loses everything between the first `<!--` and the last `-->`.
fn strip_html_comments(text: &str) -> String {
    text.split('\n')
        .map(strip_html_comments_line)
        .collect::<Vec<_>>()
        .join("\n")
}

fn strip_html_comments_line(line: &str) -> String {
    let Some(start) = line.find("<!--") else {
        return line.to_string();
    };
    let Some(relative_end) = line[start + 4..].rfind("-->") else {
        return line.to_string();
    };
    let end = start + 4 + relative_end + 3;
    format!("{}{}", &line[..start], &line[end..])
}

fn raw_field(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) => text.clone(),
        Some(other) => other.to_string(),
        None => "null".to_string(),
    }
}

fn json_field(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) => {
            serde_json::to_string(text).expect("serializing a string cannot fail")
        }
        Some(other) => other.to_string(),
        None => "null".to_string(),
    }
}

fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => false,
        Some(_) => true,
    }
}

fn check_rate_limit() -> Option<String> {
    let captured = gh_capture(&["api", "/rate_limit"])?;
    if captured.status != 0 {
        return None;
    }
    let value: Value = serde_json::from_slice(&captured.stdout).ok()?;
    let remaining = value
        .pointer("/resources/core/remaining")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    if remaining >= 50 {
        return None;
    }
    let reset = value
        .pointer("/resources/core/reset")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    let wait = reset - now + 1;
    if wait <= 0 {
        return None;
    }
    let _ = run(
        "sleep",
        &[OsString::from(wait.to_string())],
        StdioMode::Inherit,
        StdioMode::Inherit,
    );
    Some(format!(
        "Rate limit low ({remaining} remaining). Waiting {wait}s for reset..."
    ))
}

fn read_export_meta(output_dir: &str) -> String {
    let meta_file = Path::new(output_dir).join(".export-meta.json");
    let Ok(text) = fs::read_to_string(meta_file) else {
        return String::new();
    };
    match serde_json::from_str::<Value>(&text) {
        Ok(value) => match value.get("last_export_iso") {
            Some(Value::String(timestamp)) => timestamp.clone(),
            _ => String::new(),
        },
        Err(_) => String::new(),
    }
}

fn write_export_meta(output_dir: &str, slug: &str, total: usize) {
    let timestamp = utc_now_iso();
    let meta = format!(
        "{{\n  \"repo\": {},\n  \"last_export_iso\": {},\n  \"total_issues\": {total},\n  \"export_version\": 1\n}}\n",
        json_field(Some(&Value::String(slug.to_string()))),
        json_field(Some(&Value::String(timestamp)))
    );
    let path = Path::new(output_dir).join(".export-meta.json");
    let mut file = match fs::File::create(&path) {
        Ok(file) => file,
        Err(error) => {
            redirection_failure("write_export_meta", 6, &path, &error);
            return;
        }
    };
    if let Err(error) = file.write_all(meta.as_bytes()) {
        redirection_failure("write_export_meta", 6, &path, &error);
    }
}

fn utc_now_iso() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    utc_iso(seconds)
}

fn utc_iso(seconds: i64) -> String {
    let days = seconds.div_euclid(86_400);
    let seconds_of_day = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        seconds_of_day / 3600,
        (seconds_of_day % 3600) / 60,
        seconds_of_day % 60
    )
}

/// Howard Hinnant's days-from-civil inverse; valid for the whole i64 range we
/// can reach from a system clock.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    (
        year + if month <= 2 { 1 } else { 0 },
        month as u32,
        day as u32,
    )
}

#[cfg(test)]
mod tests {
    use super::{civil_from_days, strip_html_comments, utc_iso};

    #[test]
    fn timestamps_match_date_u() {
        assert_eq!(utc_iso(0), "1970-01-01T00:00:00Z");
        assert_eq!(utc_iso(1_700_000_000), "2023-11-14T22:13:20Z");
        assert_eq!(utc_iso(1_767_225_600), "2026-01-01T00:00:00Z");
    }

    #[test]
    fn civil_dates_are_consistent() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(20_454), (2026, 1, 1));
    }

    #[test]
    fn html_comments_are_removed_greedily_per_line() {
        assert_eq!(strip_html_comments("a <!--x--> b"), "a  b");
        assert_eq!(strip_html_comments("a <!--x--> b <!--y--> c"), "a  c");
        assert_eq!(
            strip_html_comments("<!--multi\nline-->"),
            "<!--multi\nline-->"
        );
    }
}
