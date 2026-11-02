//! Keep `~/.dsh/settings.yaml` on the deployment's managed blocks.
//!
//! Port of `modules/user/nix-maid/apps/dsh-models-settings.py`. The settings
//! file is the user's: the managed block is dropped and every block is
//! re-appended at EOF, so a hand edit above them survives a rebuild. A
//! hand-written section for the same key is replaced up to the next top-level
//! key, so two `key:` entries can never coexist in one YAML document.

use serde_json::Value;
use std::path::Path;

pub fn run(args: &[String]) -> i32 {
    if args.len() < 2 {
        eprintln!("usage: dsh-patch models-settings <settings.yaml> <blocks.json>");
        return 2;
    }
    let path = args[0].as_str();
    if !Path::new(path).exists() {
        println!("dsh-models: {path} absent — nothing to do");
        return 0;
    }
    let blocks_text = match std::fs::read_to_string(&args[1]) {
        Ok(text) => text,
        Err(err) => {
            eprintln!("dsh-models: {}: {err}", args[1]);
            return 1;
        }
    };
    let blocks: Vec<Value> = match serde_json::from_str(&blocks_text) {
        Ok(blocks) => blocks,
        Err(err) => {
            eprintln!("dsh-models: {}: {err}", args[1]);
            return 1;
        }
    };
    let src = match std::fs::read_to_string(path) {
        Ok(src) => src,
        Err(err) => {
            eprintln!("dsh-models: {path}: {err}");
            return 1;
        }
    };

    let mut lines: Vec<String> = src.split('\n').map(str::to_string).collect();
    for block in &blocks {
        let key = block["key"].as_str().unwrap_or_default();
        let marker = block["marker"].as_str().unwrap_or_default();
        let begin = format!("# {marker}: begin");
        let end = format!("# {marker}: end");
        if let Err(message) = remove(&mut lines, path, key, &begin, &end) {
            eprintln!("{message}");
            return 1;
        }
    }

    // Drop the blank separators left in front of the insertion point.
    while lines.len() > 1 && lines[lines.len() - 1].is_empty() && lines[lines.len() - 2].is_empty()
    {
        lines.pop();
    }
    if lines.last().map(|line| !line.is_empty()).unwrap_or(false) {
        lines.push(String::new());
    }
    for block in &blocks {
        let body = block["body"].as_str().unwrap_or_default();
        lines.extend(body.trim_end_matches('\n').split('\n').map(str::to_string));
        lines.push(String::new());
    }
    while lines.last().map(String::is_empty).unwrap_or(false) {
        lines.pop();
    }

    let out = format!("{}\n", lines.join("\n"));
    if out == src {
        println!("dsh-models: {path}: managed blocks already current");
        return 0;
    }
    if let Err(err) = std::fs::write(path, out) {
        eprintln!("dsh-models: {path}: {err}");
        return 1;
    }
    println!(
        "dsh-models: {path}: wrote {} managed block(s)",
        blocks.len()
    );
    0
}

fn remove(
    lines: &mut Vec<String>,
    path: &str,
    key: &str,
    begin: &str,
    end: &str,
) -> Result<(), String> {
    if let Some(start) = lines.iter().position(|line| line.starts_with(begin)) {
        match (start..lines.len()).find(|&index| lines[index].starts_with(end)) {
            Some(stop) => {
                lines.drain(start..stop + 1);
                return Ok(());
            }
            None => {
                return Err(format!(
                    "dsh-models: {path}: unterminated managed block {begin}"
                ))
            }
        }
    }

    // A hand-written section: replace it up to the next top-level key.
    let Some(own) = lines
        .iter()
        .position(|line| line.starts_with(&format!("{key}:")))
    else {
        return Ok(());
    };
    let mut stop = lines.len();
    for index in own + 1..lines.len() {
        let line = &lines[index];
        let first_is_space = line
            .chars()
            .next()
            .map(char::is_whitespace)
            .unwrap_or(false);
        if !line.trim().is_empty() && !first_is_space && !line.starts_with('#') {
            stop = index;
            break;
        }
    }
    lines.drain(own..stop);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(text: &str) -> Vec<String> {
        text.split('\n').map(str::to_string).collect()
    }

    #[test]
    fn managed_block_is_dropped_with_its_markers() {
        let mut text = lines("model: fast\n# m: begin\na: 1\n# m: end\ntail: 2");
        remove(&mut text, "f", "model", "# m: begin", "# m: end").unwrap();
        assert_eq!(text.join("\n"), "model: fast\ntail: 2");
    }

    #[test]
    fn hand_written_section_stops_at_the_next_top_level_key() {
        let mut text = lines("model:\n  a: 1\nother: 2\n");
        remove(&mut text, "f", "model", "# m: begin", "# m: end").unwrap();
        assert_eq!(text.join("\n"), "other: 2\n");
    }

    #[test]
    fn unterminated_managed_block_is_an_error() {
        let mut text = lines("# m: begin\na: 1\n");
        let err = remove(&mut text, "f", "model", "# m: begin", "# m: end").unwrap_err();
        assert!(err.contains("unterminated managed block"));
    }
}
