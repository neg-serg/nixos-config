//! surfingkeys-server — the tiny HTTP service the browser userscript talks to.
//!
//! Four hooks, each answered with `Cache-Control: no-store`:
//!
//!   GET /focus        send Ctrl+T to the focused Hyprland window
//!   GET /close        send Ctrl+W
//!   GET /addressbar   send Ctrl+L
//!   GET /proxy?mode=  switch the browsing proxy (`set-zen-proxy <mode>`)
//!
//! Anything else is served from `$SURFINGKEYS_DIR` (default `~/.config`), so the
//! userscript can load its own files from the same origin.
//!
//! The listener is loopback-only. The four hooks answer with CORS (including
//! the private-network preflight) because the userscript's `o` mapping fetches
//! `/addressbar` from the page context. File responses carry no CORS header:
//! the served tree is `~/.config`, which holds secrets (the SOPS age key,
//! tokens), so no web page may read them through `http://localhost:<port>`. The
//! extension's background worker is granted `<all_urls>` host permissions, so
//! it fetches the config without CORS anyway.
//!
//! The Hyprland dispatch goes through the *newest* instance socket: the
//! signature is discovered from `/run/user/<uid>/hypr/*` on every request, which
//! keeps working across compositor restarts.
//!
//! Port of `packages/local-bin/bin/surfingkeys-server`; the Python printed five
//! debug lines per request, this one prints one.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const DEFAULT_PORT: u16 = 18888;

/// Prefix of the immutable Nix store. The served tree is nix-maid-managed, so
/// its files are symlinks that end up here (see `resolve_request`).
const STORE_ROOT: &str = "/nix/store";

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn expand(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => PathBuf::from(env_or("HOME", "/")).join(rest),
        None => PathBuf::from(path),
    }
}

fn port() -> u16 {
    env_or("SURFINGKEYS_PORT", &DEFAULT_PORT.to_string())
        .trim()
        .parse()
        .unwrap_or(DEFAULT_PORT)
}

fn serve_dir() -> PathBuf {
    expand(&env_or("SURFINGKEYS_DIR", "~/.config"))
}

fn uid() -> u32 {
    Command::new("id")
        .arg("-u")
        .output()
        .ok()
        .and_then(|output| String::from_utf8_lossy(&output.stdout).trim().parse().ok())
        .unwrap_or(1000)
}

/// `HYPRLAND_INSTANCE_SIGNATURE` of the most recently touched instance.
pub fn hyprland_signature() -> Option<String> {
    if let Ok(value) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if !value.is_empty() {
            return Some(value);
        }
    }
    let dir = match std::env::var("SURFINGKEYS_HYPR_DIR") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(format!("/run/user/{}/hypr", uid())),
    };
    let entries = std::fs::read_dir(dir).ok()?;
    let mut candidates: Vec<(std::time::SystemTime, String)> = entries
        .flatten()
        .filter_map(|entry| {
            let modified = entry.metadata().ok()?.modified().ok()?;
            Some((modified, entry.file_name().to_string_lossy().to_string()))
        })
        .collect();
    candidates.sort_by(|left, right| left.0.cmp(&right.0));
    candidates.pop().map(|(_, name)| name)
}

/// Send one shortcut to the focused window through hyprctl.
fn dispatch(shortcut: &str) -> Result<(), String> {
    let signature = hyprland_signature().ok_or_else(|| "No Hyprland socket found".to_string())?;
    let hyprctl = env_or("SURFINGKEYS_HYPRCTL", "hyprctl");
    let status = Command::new(hyprctl)
        .args(["dispatch", &format!("hl.dsp.send_shortcut({{{shortcut}}})")])
        .env("HYPRLAND_INSTANCE_SIGNATURE", signature)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .status()
        .map_err(|exc| exc.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("hyprctl exited with {status}"))
    }
}

fn proxy(mode: &str) -> Result<String, String> {
    const MODES: [&str; 4] = ["direct", "telegram", "debug", "system_vpn"];
    if !MODES.contains(&mode) {
        return Err("Invalid or missing mode parameter".to_string());
    }
    let helper = env_or("SET_ZEN_PROXY", "set-zen-proxy");
    let output = Command::new(helper)
        .arg(mode)
        .stdin(Stdio::null())
        .output()
        .map_err(|exc| exc.to_string())?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn content_type(path: &Path) -> &'static str {
    match path
        .extension()
        .map(|extension| extension.to_string_lossy().to_lowercase())
        .as_deref()
    {
        Some("html") | Some("htm") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("txt") => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

/// CORS for the four hooks only. The userscript's `o` mapping runs in the page
/// context, where a private-network preflight can block the request; files must
/// stay CORS-free, otherwise any web page could read `~/.config` through
/// `http://localhost:<port>`.
const HOOK_CORS: &str = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Max-Age: 600\r\n";

fn respond_with(
    stream: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &[u8],
    extra: &str,
) {
    let head = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n{extra}\r\n",
        body.len()
    );
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(body);
    let _ = stream.flush();
}

fn respond(stream: &mut TcpStream, status: &str, content_type: &str, body: &[u8]) {
    respond_with(stream, status, content_type, body, "");
}

fn respond_hook(stream: &mut TcpStream, status: &str, content_type: &str, body: &[u8]) {
    respond_with(stream, status, content_type, body, HOOK_CORS);
}

fn respond_preflight(stream: &mut TcpStream) {
    let head = format!(
        "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n{HOOK_CORS}\r\n"
    );
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.flush();
}

fn is_hook(path: &str) -> bool {
    matches!(path, "/focus" | "/close" | "/addressbar" | "/proxy")
}

/// Where a request for a path under the served root lands.
enum Resolved {
    File(PathBuf),
    Missing,
    Forbidden,
}

/// Map a request path onto a file under `root`.
///
/// The served tree is nix-maid-managed: `~/.config/surfingkeys.js` is a symlink
/// into `~/.local/state/nix-maid/static/...`, which links to an immutable
/// `/nix/store` path. A bare `starts_with(root)` check after resolving links
/// therefore 403s the userscript's own config, so store targets are accepted
/// explicitly while every other target outside the root stays forbidden.
fn resolve_request(root: &Path, other: &str) -> Resolved {
    let relative = other.trim_start_matches('/');
    let candidate = root.join(if relative.is_empty() {
        "index.html"
    } else {
        relative
    });
    match std::fs::canonicalize(&candidate) {
        Ok(resolved) if servable(root, &resolved) => Resolved::File(resolved),
        Ok(_) => Resolved::Forbidden,
        Err(_) => Resolved::Missing,
    }
}

fn servable(root: &Path, resolved: &Path) -> bool {
    resolved.starts_with(root) || resolved.starts_with(STORE_ROOT)
}

fn handle(mut stream: TcpStream, root: &Path) {
    let mut buffer = [0u8; 4096];
    let read = match stream.read(&mut buffer) {
        Ok(read) if read > 0 => read,
        _ => return,
    };
    let request = String::from_utf8_lossy(&buffer[..read]).to_string();
    let target = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .unwrap_or("/")
        .to_string();
    println!("surfingkeys: {target}");
    let (path, query) = match target.split_once('?') {
        Some((path, query)) => (path.to_string(), query.to_string()),
        None => (target.clone(), String::new()),
    };
    // Private-network preflight for the hooks (`fetch` from the page context).
    let method = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().next())
        .unwrap_or("");
    if method == "OPTIONS" {
        if is_hook(&path) {
            respond_preflight(&mut stream);
        } else {
            respond(
                &mut stream,
                "405 Method Not Allowed",
                "text/plain",
                b"Method Not Allowed",
            );
        }
        return;
    }
    match path.as_str() {
        "/focus" => match dispatch("mods=\"CTRL\",key=\"T\"") {
            Ok(()) => respond_hook(&mut stream, "200 OK", "text/plain", b"OK"),
            Err(exc) => {
                println!("surfingkeys: /focus error: {exc}");
                respond_hook(
                    &mut stream,
                    "500 Internal Server Error",
                    "text/plain",
                    exc.as_bytes(),
                )
            }
        },
        "/close" => match dispatch("mods=\"CTRL\",key=\"W\"") {
            Ok(()) => respond_hook(&mut stream, "200 OK", "text/plain", b"OK"),
            Err(exc) => respond_hook(
                &mut stream,
                "500 Internal Server Error",
                "text/plain",
                exc.as_bytes(),
            ),
        },
        "/addressbar" => match dispatch("mods=\"CTRL\",key=\"L\"") {
            Ok(()) => respond_hook(&mut stream, "200 OK", "text/plain", b"OK"),
            Err(exc) => respond_hook(
                &mut stream,
                "500 Internal Server Error",
                "text/plain",
                exc.as_bytes(),
            ),
        },
        "/proxy" => {
            let mode = query
                .split('&')
                .find_map(|pair| pair.strip_prefix("mode="))
                .unwrap_or("");
            match proxy(mode) {
                Ok(out) => respond_hook(&mut stream, "200 OK", "text/plain", out.as_bytes()),
                Err(exc) => {
                    println!("surfingkeys: /proxy error: {exc}");
                    respond_hook(
                        &mut stream,
                        "500 Internal Server Error",
                        "text/plain",
                        exc.as_bytes(),
                    )
                }
            }
        }
        other => match resolve_request(root, other) {
            Resolved::File(path) => match std::fs::read(&path) {
                Ok(body) => respond(&mut stream, "200 OK", content_type(&path), &body),
                Err(_) => respond(&mut stream, "404 Not Found", "text/plain", b"Not Found"),
            },
            Resolved::Forbidden => {
                respond(&mut stream, "403 Forbidden", "text/plain", b"Forbidden")
            }
            Resolved::Missing => respond(&mut stream, "404 Not Found", "text/plain", b"Not Found"),
        },
    }
}

fn main() -> std::process::ExitCode {
    let port = port();
    let root = std::fs::canonicalize(serve_dir()).unwrap_or_else(|_| serve_dir());
    // Loopback only (the Python predecessor bound every interface): the served
    // tree is `~/.config`, so LAN access would expose its secrets.
    let listener = match TcpListener::bind(("127.0.0.1", port)) {
        Ok(listener) => listener,
        Err(exc) => {
            eprintln!("surfingkeys-server: cannot bind :{port}: {exc}");
            return std::process::ExitCode::from(1);
        }
    };
    println!("Serving at port {port} from {}", root.display());
    for stream in listener.incoming().flatten() {
        handle(stream, &root);
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_symlink_targets_are_servable() {
        let root = Path::new("/home/someone/.config");
        // nix-maid layout: config file -> static link -> store path.
        assert!(servable(
            root,
            Path::new("/nix/store/abc-nix-maid-.config-surfingkeys.js")
        ));
        assert!(servable(
            root,
            Path::new("/home/someone/.config/surfingkeys.js")
        ));
        // Everything else outside the served root stays forbidden.
        assert!(!servable(root, Path::new("/home/someone/.ssh/id_rsa")));
        assert!(!servable(root, Path::new("/etc/passwd")));
    }

    #[test]
    fn traversal_and_foreign_symlinks_are_forbidden() {
        let dir = std::env::temp_dir().join(format!("surfingkeys-serve-{}", std::process::id()));
        let root = dir.join("config");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("local.js"), b"ok").unwrap();
        std::fs::write(dir.join("outside.js"), b"secret").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(dir.join("outside.js"), root.join("escape.js")).unwrap();
        let root = std::fs::canonicalize(&root).unwrap();
        assert!(matches!(
            resolve_request(&root, "/local.js"),
            Resolved::File(_)
        ));
        assert!(matches!(
            resolve_request(&root, "/../outside.js"),
            Resolved::Forbidden
        ));
        assert!(matches!(
            resolve_request(&root, "/escape.js"),
            Resolved::Forbidden
        ));
        assert!(matches!(
            resolve_request(&root, "/missing.js"),
            Resolved::Missing
        ));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn signatures_come_from_the_newest_instance() {
        let dir = std::env::temp_dir().join(format!("surfingkeys-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("old")).unwrap();
        std::fs::create_dir_all(dir.join("new")).unwrap();
        std::env::set_var("SURFINGKEYS_HYPR_DIR", &dir);
        std::env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
        // Touch "new" last so it is the newest entry.
        std::thread::sleep(std::time::Duration::from_millis(20));
        let touch = dir.join("new");
        std::fs::write(touch.join("marker"), b"x").unwrap();
        assert_eq!(hyprland_signature().as_deref(), Some("new"));
        std::env::remove_var("SURFINGKEYS_HYPR_DIR");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn proxy_modes_are_validated() {
        // A real stub, because the nix build sandbox has no /bin/true.
        let dir = std::env::temp_dir().join(format!("surfingkeys-proxy-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let stub = dir.join("set-zen-proxy");
        std::fs::write(&stub, "#!/bin/sh\necho \"proxy-set:$1\"\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&stub).unwrap().permissions().mode();
            std::fs::set_permissions(&stub, std::fs::Permissions::from_mode(mode | 0o111)).unwrap();
        }
        std::env::set_var("SET_ZEN_PROXY", &stub);
        assert_eq!(proxy("direct").unwrap(), "proxy-set:direct\n");
        assert_eq!(proxy("telegram").unwrap(), "proxy-set:telegram\n");
        assert_eq!(
            proxy("bogus").unwrap_err(),
            "Invalid or missing mode parameter"
        );
        std::env::remove_var("SET_ZEN_PROXY");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn content_types_follow_the_extension() {
        assert_eq!(
            content_type(Path::new("a.js")),
            "text/javascript; charset=utf-8"
        );
        assert_eq!(
            content_type(Path::new("a.html")),
            "text/html; charset=utf-8"
        );
        assert_eq!(content_type(Path::new("a.bin")), "application/octet-stream");
    }
}
