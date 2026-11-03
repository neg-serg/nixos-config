//! surfingkeys-extension-patch: keep the force-installed SurfingKeys extension
//! loading its config from the local server.
//!
//! Port of `packages/local-bin/bin/surfingkeys-extension-patch` (bash).
//! Vivaldi updates extensions in place and the minifier renames identifiers
//! between releases, so every step patches the newest version directory, is
//! guarded by the marker it writes, and *fails loudly* when neither the marker
//! nor the anchor is present — a silent skip is how a `403 Forbidden` response
//! body once stayed registered as the settings userScript.
//!
//! Kept from the original: the log lines (`logger`/`logger -p user.err` with
//! the exact `//` in the version path), the patch text byte-for-byte, the
//! version-directory selection (`sort -V` newest) and the exit status
//! (0 patched / 1 anchors moved). `grep`/`sed`/`ls`/`sort`/`cat` are native.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use local_bin_system as sh;

const URL: &str = "http://localhost:18888/surfingkeys.js";
const EXTENSION: &str = "gfbliohnnapiefjpjlpjnehglfpaknnc";

const URL_ANCHOR: &str = "(()=>{\"use strict\"";
const CONFIG_URL_ANCHOR: &str = "e.localPath?B(e.localPath,";
const FETCH_ANCHOR: &str = "B(e.localPath,function(t){e.snippets=t,o(e)},";
const FETCH_REPLACEMENT: &str = "B(e.localPath,function(t){e.snippets=t,NEG_SK_REGISTER2(t),o(e)},";
const OLD_REGISTER: &str = "const NEG_SK_REGISTER=function(s){var c=";
const ZEBRA: &str = "background-color: #f8f8f8;";

/// The heredoc the original prepends: one line, `\n` literal inside the
/// injected code, newline at the end.
const REGISTER_HELPER: &str = r#"const NEG_SK_REGISTER2=function(s){var c="import(\"./api.js\").then(function(m){m.default(\""+chrome.runtime.getURL("/")+"\",function(api,settings){"+s+"\n})});";chrome.userScripts.getScripts({ids:["settingsSnippets"]},function(r){if(!chrome.runtime.lastError&&r&&r.length&&r[0].js&&r[0].js[0]&&r[0].js[0].code===c){return}chrome.userScripts.unregister({ids:["settingsSnippets"]},function(){chrome.userScripts.register([{allFrames:!0,id:"settingsSnippets",matches:["*://*/*","file:///*"],js:[{code:c}],runAt:"document_start"}])})})};
"#;

/// `logger` is the only program left: the unit supplies util-linux for it.
/// A missing logger is a shell 127 and a failing one aborts with its status.
fn log(message: &str, error: bool) {
    let mut command = Command::new("logger");
    if error {
        command.args(["-p", "user.err"]);
    }
    command.arg(format!("surfingkeys-patch: {message}"));
    match command.status() {
        Ok(status) if status.success() => {}
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}

struct Patcher {
    failed: bool,
    background: String,
}

impl Patcher {
    fn missing(&mut self, message: &str) {
        log(message, true);
        self.failed = true;
    }

    fn note(&mut self, message: &str) {
        log(message, false);
    }

    fn write(&self, content: &str) {
        write_or_exit(&self.background, content);
    }
}

fn write_or_exit(path: &str, content: &str) {
    let target = Path::new(path);
    let temporary = format!("{path}.tmp");
    if let Err(error) = fs::write(&temporary, content) {
        sh::err_line(&format!(
            "surfingkeys-extension-patch: cannot write {temporary}: {error}"
        ));
        std::process::exit(1);
    }
    if let Err(error) = fs::rename(&temporary, target) {
        let _ = fs::remove_file(&temporary);
        sh::err_line(&format!(
            "surfingkeys-extension-patch: cannot replace {path}: {error}"
        ));
        std::process::exit(1);
    }
}

/// The newest version directory, spelled the way `ls -d "$EXT_BASE"/*/` spells
/// it: with a trailing slash, which the original then doubles in every path.
fn newest_version(base: &str) -> Option<String> {
    let mut versions: Vec<String> = Vec::new();
    let entries = match fs::read_dir(base) {
        Ok(entries) => entries,
        // `VER_DIR=$(ls … | sort -V | tail -1)` under `set -euo pipefail`:
        // a failing `ls` aborts the script with ls' status 2.
        Err(_) => std::process::exit(2),
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') || !entry.path().is_dir() {
            continue;
        }
        versions.push(format!("{base}/{name}/"));
    }
    versions.sort_by(|left, right| sh::version_cmp(left, right));
    versions.pop()
}

fn main() {
    let base = format!(
        "{}/.config/vivaldi/Default/Extensions/{EXTENSION}",
        sh::home()
    );
    let Some(version_dir) = newest_version(&base) else {
        // The original's `[ -z "$VER_DIR" ] && exit 0` is unreachable under
        // `set -e` + `pipefail` (the failing `ls` already aborted with 2), so
        // the port keeps the observable status.
        std::process::exit(2);
    };
    let background = format!("{version_dir}/background.js");
    let markdown = PathBuf::from(format!("{version_dir}/pages/markdown.css"));

    let original = match sh::read_text(Path::new(&background)) {
        Some(content) => content,
        None => {
            // `grep`/`sed`/`cat` on the missing file would abort the shell at
            // the first `set -e` command; the port reports the first anchor
            // and leaves the file alone.
            log(
                &format!("URL-injection anchor not found in {background}"),
                true,
            );
            std::process::exit(1);
        }
    };

    let mut patcher = Patcher {
        failed: false,
        background: background.clone(),
    };
    let mut content = original;

    // 1. Config URL injection at worker start.
    if !content.contains("NEG_SK_URL") {
        if content.split('\n').any(|line| line.starts_with(URL_ANCHOR)) {
            let backup = format!("{background}.orig");
            if let Err(error) = fs::copy(&background, &backup) {
                sh::err_line(&format!(
                    "cp: cannot copy {background} to {backup}: {error}"
                ));
                std::process::exit(1);
            }
            let replacement = format!(
                "const NEG_SK_URL=\"{URL}\";\n\
                 chrome.storage.sync.set({{localPath:NEG_SK_URL}});\n\
                 chrome.storage.local.set({{localPath:NEG_SK_URL}});\n\
                 {URL_ANCHOR}"
            );
            content = sh::replace_first_per_line(&content, URL_ANCHOR, &replacement);
            patcher.write(&content);
            patcher.note(&format!("Patched {background} (URL injection)"));
        } else {
            patcher.missing(&format!("URL-injection anchor not found in {background}"));
        }
    }

    // 2. Re-registration helper (reads the current registration first and
    //    leaves it alone when the code already matches).
    if !content.contains("NEG_SK_REGISTER2") {
        content = sh::delete_lines_starting_with(&content, OLD_REGISTER);
        let mut patched = String::with_capacity(REGISTER_HELPER.len() + content.len());
        patched.push_str(REGISTER_HELPER);
        patched.push_str(&content);
        content = patched;
        patcher.write(&content);
        patcher.note(&format!(
            "Patched {background} (config re-registration helper)"
        ));
    }

    // 3. Force the local config URL at the read point.
    let config_url_needle = format!("(e.localPath=\"{URL}\",e.localPath)");
    if !content.contains(&config_url_needle) {
        if content.contains(CONFIG_URL_ANCHOR) {
            let replacement = format!("(e.localPath=\"{URL}\",e.localPath)?B(e.localPath,");
            content = sh::replace_first_per_line(&content, CONFIG_URL_ANCHOR, &replacement);
            patcher.write(&content);
            patcher.note(&format!("Patched {background} (hardcoded config URL)"));
        } else {
            patcher.missing(&format!("config-URL read anchor not found in {background}"));
        }
    }

    // 4. Refresh the registered userScript after every successful fetch.
    if !content.contains("NEG_SK_REGISTER2(t)") {
        if content.contains(FETCH_ANCHOR) {
            content = sh::replace_first_per_line(&content, FETCH_ANCHOR, FETCH_REPLACEMENT);
            patcher.write(&content);
            patcher.note(&format!(
                "Patched {background} (refresh registration after fetch)"
            ));
        } else if content.contains("NEG_SK_REGISTER(t)") {
            content = sh::replace_all(&content, "NEG_SK_REGISTER(t)", "NEG_SK_REGISTER2(t)");
            patcher.write(&content);
            patcher.note(&format!(
                "Patched {background} (refresh registration after fetch, upgraded)"
            ));
        } else {
            patcher.missing(&format!("fetch-callback anchor not found in {background}"));
        }
    }

    // 5. Remove zebra striping from the markdown preview tables (cosmetic).
    if markdown.is_file() {
        if let Some(css) = sh::read_text(&markdown) {
            if css.contains(ZEBRA) {
                let patched =
                    sh::replace_first_per_line(&css, ZEBRA, "background-color: transparent;");
                if let Err(error) = fs::write(&markdown, patched) {
                    sh::err_line(&format!(
                        "sed: cannot edit {}: {error}",
                        markdown.to_string_lossy()
                    ));
                    std::process::exit(1);
                }
                patcher.note(&format!(
                    "Patched {} (no zebra)",
                    markdown.to_string_lossy()
                ));
            }
        }
    }

    // A critical patch that silently stopped matching means the minifier moved
    // and the anchors need an update; fail the unit so the breakage is visible.
    let mut critical = Vec::new();
    if !content.contains("NEG_SK_URL") {
        critical.push("critical patch missing: URL injection");
    }
    if !content.contains("NEG_SK_REGISTER2") {
        critical.push("critical patch missing: registration helper");
    }
    if !content.contains("NEG_SK_REGISTER2(t)") {
        critical.push("critical patch missing: registration refresh");
    }
    if !content.contains(&config_url_needle) {
        critical.push("critical patch missing: hardcoded config URL");
    }
    for message in critical {
        log(message, true);
        patcher.failed = true;
    }

    std::process::exit(i32::from(patcher.failed));
}
