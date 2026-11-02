//! Drop the retired workflow-provider row from the installed liangshen preset.
//!
//! Port of `modules/user/nix-maid/apps/dsh-tui-liangshen-prune.py`. dsh-TUI
//! ships `presets/liangshen/agent.cordis.yml` with two workflow-provider rows:
//! the 0.1.x `@deepseek-ai/dsh-workflow-worker-thread` fallback and its 0.2.0
//! replacement `@deepseek-ai/dsh-workflow-ptc`. The fallback carries a
//! `disabled: !!js` guard, but the harness reads declarations statically, so
//! the unevaluated guard never reads as `true`: the row is denied and with it
//! the whole `liangshen-plugins` Include. On a runtime that ships the
//! replacement the fallback is dead code, and the caretaker removes it from
//! the INSTALLED copy on every activation and login.
//!
//! Idempotent and conservative: a file without the row - or one that lost the
//! replacement row too, where the fallback would be the live one again - is
//! left untouched. The rewrite is atomic (temp file + rename), so a hard-linked
//! pnpm store copy is never written through.
//!
//! The Python version re-parsed the pruned document with PyYAML when that
//! module was importable (a convenience net against a wrong cut). The cut here
//! is the same span logic, and the parse net is dropped: a YAML parser is not
//! worth carrying for a check the deployment's python3 only sometimes had.

use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

const ROW_ID: &str = "workflow-worker-thread";
const ROW_PLUGIN: &str = "@deepseek-ai/dsh-workflow-worker-thread";
const REPLACEMENT_PLUGIN: &str = "@deepseek-ai/dsh-workflow-ptc";
const ROW_LINE: &str = "- id: workflow-worker-thread";

pub fn run(args: &[String]) -> i32 {
    if args.len() != 1 {
        eprintln!("usage: dsh-patch liangshen-prune <agent.cordis.yml>");
        return 2;
    }
    let path = args[0].as_str();
    if !Path::new(path).is_file() {
        return 0;
    }
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(err) => {
            eprintln!("dsh-tui-ensure: cannot read {path}: {err}");
            return 1;
        }
    };
    let lines: Vec<&str> = text.split_inclusive('\n').collect();
    let Some((start, end)) = row_span(&lines) else {
        return 0;
    };
    let block = lines[start..end].concat();
    if !block.contains(ROW_PLUGIN) {
        eprintln!("dsh-tui-ensure: {path}: '{ROW_ID}' does not name {ROW_PLUGIN}; left alone");
        return 0;
    }
    if !text.contains(REPLACEMENT_PLUGIN) {
        eprintln!(
            "dsh-tui-ensure: {path}: the {REPLACEMENT_PLUGIN} replacement is missing; '{ROW_ID}' left alone"
        );
        return 0;
    }
    let pruned = format!("{}{}", lines[..start].concat(), lines[end..].concat());
    if let Err(err) = write_atomic(Path::new(path), &pruned) {
        eprintln!("dsh-tui-ensure: cannot rewrite {path}: {err}");
        return 1;
    }
    println!("dsh-tui-ensure: pruned the retired '{ROW_ID}' row from {path}");
    0
}

/// Span of the retired row's YAML block, or `None` when it is absent.
///
/// The block runs from its `- id:` line to the next item at the same indent (or
/// a line indented further left); a same-indent comment does not end it, since
/// cutting there would leave the block's remaining keys dangling. Trailing
/// blank lines stay with the next item.
fn row_span(lines: &[&str]) -> Option<(usize, usize)> {
    for (index, line) in lines.iter().enumerate() {
        let content = line.trim_end_matches('\n').trim_end();
        let indent = content.len() - content.trim_start_matches(' ').len();
        if &content[indent..] != ROW_LINE {
            continue;
        }
        let mut end = lines.len();
        for (following, candidate) in lines.iter().enumerate().skip(index + 1) {
            if candidate.trim().is_empty() {
                continue;
            }
            let current = candidate.len() - candidate.trim_start_matches(' ').len();
            let starts_item = candidate.trim_start_matches(' ').starts_with("- ");
            if current < indent || (current == indent && starts_item) {
                end = following;
                break;
            }
        }
        while end > index + 1 && lines[end - 1].trim().is_empty() {
            end -= 1;
        }
        return Some((index, end));
    }
    None
}

fn write_atomic(path: &Path, text: &str) -> io::Result<()> {
    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    let mode = fs::metadata(path)?.permissions().mode() & 0o7777;
    let mut attempt = 0u32;
    let (temporary, mut file) = loop {
        let name = format!(".dsh-liangshen-prune-{}-{attempt}.tmp", std::process::id());
        let candidate = directory.join(name);
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(file) => break (candidate, file),
            Err(err) if err.kind() == io::ErrorKind::AlreadyExists && attempt < 100 => {
                attempt += 1;
            }
            Err(err) => return Err(err),
        }
    };
    let result = file
        .write_all(text.as_bytes())
        .and_then(|()| fs::set_permissions(&temporary, fs::Permissions::from_mode(mode)))
        .and_then(|()| fs::rename(&temporary, path));
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn span_runs_to_the_next_row_at_the_same_indent() {
        let text = "\
- id: a
  plugin: p
- id: workflow-worker-thread
  plugin: @deepseek-ai/dsh-workflow-worker-thread
  disabled: !!js true
- id: b
";
        let lines: Vec<&str> = text.split_inclusive('\n').collect();
        let (start, end) = row_span(&lines).unwrap();
        assert_eq!(start, 2);
        assert_eq!(end, 5);
        assert!(lines[start..end].concat().contains(ROW_PLUGIN));
    }

    #[test]
    fn a_missing_row_has_no_span() {
        let text = "- id: a\n- id: b\n";
        let lines: Vec<&str> = text.split_inclusive('\n').collect();
        assert!(row_span(&lines).is_none());
    }
}
