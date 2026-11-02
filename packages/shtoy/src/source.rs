//! Source resolution: stdin, a local file, a cached or shipped id, and the
//! import/mirror/API paths that populate the cache.
//!
//! Order of the shell's `case` and `elif` chain, preserved here:
//! 1. `-` reads stdin into a temporary file (`--save` rejects it);
//! 2. an existing file is run directly (import/mirror/save reject it);
//! 3. otherwise the argument must parse as a Shadertoy id;
//! 4. an existing `$CACHE/shtoy/<id>.frag` always wins, even for --import;
//! 5. --import caches the clipboard, --mirror caches a Sourcegraph match;
//! 6. a shipped `$CONFIG/shtoy/shaders/<id>.frag` is used next;
//! 7. with an API key, the Shadertoy API result is cached;
//! 8. otherwise the id is reported as not cached.

use std::ffi::OsStr;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::api::{self, ApiResponse};
use crate::cli::{Mode, Options};
use crate::env::Env;
use crate::http::{Http, Request};
use crate::mirror;
use crate::paths::Paths;
use crate::tempfile::TempFile;
use crate::viewer::find_program;
use crate::{Die, PROG};

pub const DEFAULT_API_BASE: &str = "https://www.shadertoy.com/api/v1";

pub struct Resolved {
    pub raw: PathBuf,
    /// Kept alive so the stdin copy survives until esshader has read it.
    pub temp: Option<TempFile>,
}

/// URL or bare id -> id; the shell trimmed one trailing slash, the query and
/// fragment, then took the last path segment and required 6-8 ASCII
/// alphanumerics.
pub fn shader_id(argument: &OsStr) -> Option<String> {
    let text = argument.to_str()?;
    let text = text.strip_suffix('/').unwrap_or(text);
    let text = text.split('?').next().unwrap_or("");
    let text = text.split('#').next().unwrap_or("");
    let text = text.rsplit('/').next().unwrap_or("");
    if (6..=8).contains(&text.len()) && text.bytes().all(|byte| byte.is_ascii_alphanumeric()) {
        Some(text.to_string())
    } else {
        None
    }
}

/// `SHADERTOY_API_KEY`, else the whitespace-stripped content of
/// `$XDG_CONFIG_HOME/shtoy/api_key`; an empty result means "no key".
pub fn api_key(environment: &Env, paths: &Paths) -> Option<String> {
    if let Some(value) = environment.get_nonempty("SHADERTOY_API_KEY") {
        return Some(value.to_string_lossy().into_owned());
    }
    let bytes = fs::read(&paths.api_key_file).ok()?;
    let filtered: Vec<u8> = bytes
        .into_iter()
        .filter(|byte| !is_ascii_space(*byte))
        .collect();
    if filtered.is_empty() {
        return None;
    }
    Some(String::from_utf8_lossy(&filtered).into_owned())
}

pub fn resolve(
    options: &Options,
    argument: &OsStr,
    paths: &Paths,
    environment: &Env,
    http: &dyn Http,
    api_key: Option<&str>,
) -> Result<Resolved, Die> {
    if argument == OsStr::new("-") {
        if options.save {
            return Err(Die::new("--save takes a Shadertoy id or URL, not a stream"));
        }
        let temporary = TempFile::create(environment, "shtoy-stdin-", ".frag")?;
        let mut content = Vec::new();
        std::io::stdin()
            .read_to_end(&mut content)
            .map_err(|error| Die::new(format!("cannot read stdin: {error}")))?;
        fs::write(temporary.path(), content).map_err(|error| {
            Die::new(format!(
                "cannot write {}: {error}",
                temporary.path().display()
            ))
        })?;
        return Ok(Resolved {
            raw: temporary.path().to_path_buf(),
            temp: Some(temporary),
        });
    }

    if Path::new(argument).is_file() {
        if options.mode != Mode::Run || options.save {
            return Err(Die::new(
                "--import/--mirror/--save take a Shadertoy id or URL, not a file",
            ));
        }
        return Ok(Resolved {
            raw: PathBuf::from(argument),
            temp: None,
        });
    }

    let id = shader_id(argument).ok_or_else(|| {
        Die::new(format!(
            "not a file, and not a Shadertoy id: {}",
            argument.to_string_lossy()
        ))
    })?;
    let url = format!("https://www.shadertoy.com/view/{id}");
    let cached = paths.cache_dir.join(format!("{id}.frag"));
    if cached.is_file() {
        return Ok(Resolved {
            raw: cached,
            temp: None,
        });
    }

    if options.mode == Mode::Import {
        fs::create_dir_all(&paths.cache_dir).map_err(|error| {
            Die::new(format!(
                "cannot create {}: {error}",
                paths.cache_dir.display()
            ))
        })?;
        // The shell redirected clipboard_source into "$raw.part", so the empty
        // part exists even when the clipboard read dies; keep that artifact so
        // a failed import leaves the cache in the same state as before.
        let part = create_part(&cached)?;
        let source = clipboard_source(&url, environment)?;
        commit_part(&part, &cached, &source)?;
        eprintln!("{PROG}: cached {}", cached.display());
        return Ok(Resolved {
            raw: cached,
            temp: None,
        });
    }

    if options.mode == Mode::Mirror {
        fs::create_dir_all(&paths.cache_dir).map_err(|error| {
            Die::new(format!(
                "cannot create {}: {error}",
                paths.cache_dir.display()
            ))
        })?;
        let proxy = mirror::proxy_from_env(environment);
        let sourcegraph_url = environment
            .get_nonempty_string("SHTOY_SOURCEGRAPH_URL")
            .unwrap_or_else(|| mirror::DEFAULT_SOURCEGRAPH_URL.to_string());
        let raw_base = environment
            .get_nonempty_string("SHTOY_RAW_BASE")
            .unwrap_or_else(|| mirror::DEFAULT_RAW_BASE.to_string());
        let config = mirror::MirrorConfig {
            sourcegraph_url: &sourcegraph_url,
            raw_base: &raw_base,
            proxy: proxy.as_deref(),
        };
        match mirror::mirror_source(&id, &config, http) {
            Some(source) => {
                write_cache(&cached, &source)?;
                eprintln!("{PROG}: fetched {} -> {}", id, cached.display());
                Ok(Resolved {
                    raw: cached,
                    temp: None,
                })
            }
            None => Err(Die::new(format!(
                "no usable mirror copy of {id} — copy the source on {url}, then run: shtoy --import {id}"
            ))),
        }
    } else {
        let shipped = paths.shader_dir.join(format!("{id}.frag"));
        if shipped.is_file() {
            return Ok(Resolved {
                raw: shipped,
                temp: None,
            });
        }
        if let Some(key) = api_key {
            fs::create_dir_all(&paths.cache_dir).map_err(|error| {
                Die::new(format!(
                    "cannot create {}: {error}",
                    paths.cache_dir.display()
                ))
            })?;
            // Same redirect ordering as the shell: failures inside api_source
            // leave the empty part behind, while an empty successful response
            // is removed by the caller's `-s` check.
            let part = create_part(&cached)?;
            let source = api_source(&id, key, environment, http)?;
            if source.is_empty() {
                let _ = fs::remove_file(&part);
                return Err(Die::new(format!("the API returned no Image pass for {id}")));
            }
            commit_part(&part, &cached, &source)?;
            eprintln!("{PROG}: fetched {} -> {}", id, cached.display());
            return Ok(Resolved {
                raw: cached,
                temp: None,
            });
        }
        Err(Die::new(format!(
            "no cached copy of {id} — copy the shader source on {url}, then run: shtoy --import {id}"
        )))
    }
}

fn clipboard_source(url: &str, environment: &Env) -> Result<Vec<u8>, Die> {
    let program = find_program("wl-paste", environment)
        .ok_or_else(|| Die::new("missing dependency: wl-paste"))?;
    // The shell used `wl-paste --no-newline 2>/dev/null || true`.
    let mut source = match Command::new(&program)
        .arg("--no-newline")
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) => output.stdout,
        Err(_) => Vec::new(),
    };
    if source.is_empty() {
        return Err(Die::new(format!(
            "clipboard is empty — copy the shader source on {url} first"
        )));
    }
    if !contains(&source, b"mainImage") && !contains(&source, b"void main") {
        return Err(Die::new(
            "clipboard does not look like shader source (neither mainImage nor main)",
        ));
    }
    // `printf '%s\n'` normalized the copied text to one trailing newline.
    source.push(b'\n');
    Ok(source)
}

fn api_source(id: &str, key: &str, environment: &Env, http: &dyn Http) -> Result<Vec<u8>, Die> {
    let base = environment
        .get_nonempty_string("SHTOY_API_BASE")
        .unwrap_or_else(|| DEFAULT_API_BASE.to_string());
    let url = format!("{}/shaders/{}?key={}", base.trim_end_matches('/'), id, key);
    let body = http
        .fetch(&Request {
            url: &url,
            timeout: Duration::from_secs(20),
            proxy: None,
            headers: &[],
        })
        .map_err(|_| {
            Die::new(format!(
                "Shadertoy API fetch failed for {id} (Cloudflare challenges curl from here — use --import)"
            ))
        })?;
    match api::image_pass(&body) {
        ApiResponse::Code(code) => Ok(code),
        ApiResponse::NoShaderData => Err(Die::new(format!(
            "Shadertoy API returned no shader data for {id} (challenge page, bad key or unknown id?)"
        ))),
        // The shell's api_source still exited successfully with empty output;
        // its caller removed the part and reported the missing Image pass.
        ApiResponse::NoImagePass => Ok(Vec::new()),
    }
}

/// `$raw.part` followed by `mv -f`, like the shell's cache writes.
fn write_cache(target: &Path, source: &[u8]) -> Result<(), Die> {
    let part = create_part(target)?;
    commit_part(&part, target, source)
}

/// The empty redirect target the shell created before running the producer.
fn create_part(target: &Path) -> Result<PathBuf, Die> {
    let part = part_path(target);
    fs::write(&part, b"")
        .map_err(|error| Die::new(format!("cannot write {}: {error}", part.display())))?;
    Ok(part)
}

fn commit_part(part: &Path, target: &Path, source: &[u8]) -> Result<(), Die> {
    fs::write(part, source)
        .map_err(|error| Die::new(format!("cannot write {}: {error}", part.display())))?;
    fs::rename(part, target).map_err(|error| {
        let _ = fs::remove_file(part);
        Die::new(format!("cannot rename {}: {error}", part.display()))
    })
}

fn part_path(target: &Path) -> PathBuf {
    let mut part = target.as_os_str().to_os_string();
    part.push(".part");
    PathBuf::from(part)
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
        .is_some()
}

fn is_ascii_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

#[cfg(test)]
mod tests {
    use super::shader_id;
    use std::ffi::OsStr;

    fn id(text: &str) -> Option<String> {
        shader_id(OsStr::new(text))
    }

    #[test]
    fn bare_ids_are_accepted() {
        assert_eq!(id("AbCd12").as_deref(), Some("AbCd12"));
        assert_eq!(id("AbCd1234").as_deref(), Some("AbCd1234"));
    }

    #[test]
    fn view_urls_and_query_fragments_are_trimmed() {
        for url in [
            "https://www.shadertoy.com/view/AbCd12",
            "https://www.shadertoy.com/view/AbCd12/",
            "https://www.shadertoy.com/view/AbCd12?x=1",
            "https://www.shadertoy.com/view/AbCd12#comment",
            "https://example.com/view/AbCd12",
        ] {
            assert_eq!(id(url).as_deref(), Some("AbCd12"), "{url}");
        }
    }

    #[test]
    fn a_query_after_a_trailing_slash_is_not_an_id() {
        // The shell trimmed one trailing slash first, then the query, so the
        // slash before "?x=1" survives and the basename is empty.
        assert_eq!(id("https://www.shadertoy.com/view/AbCd12/?x=1#y"), None);
        assert_eq!(id("https://www.shadertoy.com/view/AbCd12/?x=1"), None);
    }

    #[test]
    fn bad_ids_are_rejected() {
        assert_eq!(id("abc12"), None);
        assert_eq!(id("abcdefghi"), None);
        assert_eq!(id("AbCd-12"), None);
        assert_eq!(id("https://www.shadertoy.com/view/"), None);
        assert_eq!(id(""), None);
    }
}
