//! sw: unified wallpaper downloader (wallhaven + unsplash).
//!
//! Port of `packages/local-bin/bin/sw` (bash). The HTTP work stays in `curl`
//! with the original argv (`-fsS --retry 3`, `-o DEST URL`); JSON parsing,
//! URL query building and jq's `@uri` escaping are native so the helper no
//! longer depends on `jq` output for correctness (the original's `require jq`
//! gate is kept, see `main`).
//!
//! Kept from the original: both API URLs byte-for-byte (including the quirky
//! `?&categories=` when no query is given and the unencoded values), the
//! random page/image pick, key resolution (`-k`, then the environment, then
//! `~/.gemini/unsplash.key`), the printed destination and the error text.

use std::fs;
use std::path::Path;
use std::process::Stdio;

use local_bin_system as sh;
use serde_json::Value;

const HELP: &str = r#"sw: unified wallpaper downloader
Usage: sw [options]

General:
  -S, --source NAME         Source: wallhaven (default) or unsplash
  -q, --query STR           Search terms
  -l, --location DIR        Download directory
  -k, --apikey KEY          API key (overrides env/file)
  -h, --help                Show this help

Wallhaven Specific:
  -C, --colors HEX          Dominant colors (e.g. 424153)
  -a, --atleast WxH         Min resolution (default: 3840x2160)
  -p, --purity STR          Purity (default: 100)
  -c, --categories STR      Categories (default: 100)
  -r, --ratios LIST         Ratios (default: 16x9)
  -s, --sorting MODE        Sorting (random, latest, top...)
  -O, --order ORDER         Order (asc/desc)

Unsplash Specific:
  -o, --orientation STR     Orientation (landscape, portrait)
  -f, --featured            Limit to featured photos
"#;

#[derive(Default)]
struct Options {
    source: String,
    location: String,
    query: String,
    apikey: String,
    wh_atleast: String,
    wh_purity: String,
    wh_categories: String,
    wh_order: String,
    wh_ratios: String,
    wh_sorting: String,
    wh_colors: String,
    us_orientation: String,
    us_featured: String,
}

fn prog() -> String {
    sh::prog("sw")
}

fn die(message: &str) -> ! {
    sh::die(&prog(), message)
}

/// A small xorshift seeded from the clock and the pid; `$RANDOM` is not
/// available, but only the range matters (`% 10 + 1` / one image of the list).
fn random_u64() -> u64 {
    use std::io::Read;
    if let Ok(mut file) = fs::File::open("/dev/urandom") {
        let mut bytes = [0u8; 8];
        if file.read_exact(&mut bytes).is_ok() {
            return u64::from_le_bytes(bytes);
        }
    }
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos() as u64)
        .unwrap_or(0);
    let pid = std::process::id() as u64;
    let mut state = nanos ^ pid.rotate_left(17) ^ 0x9e37_79b9_7f4a_7c15;
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    state
}

fn random_below(bound: usize) -> usize {
    if bound <= 1 {
        return 0;
    }
    (random_u64() % bound as u64) as usize
}

fn env_pictures() -> String {
    let home = sh::home();
    let base = sh::env_or("XDG_PICTURES_DIR", &format!("{home}/pic"));
    format!("{base}/wl")
}

fn parse(arguments: &[String]) -> Options {
    let mut options = Options {
        source: "wallhaven".to_string(),
        location: env_pictures(),
        query: String::new(),
        apikey: String::new(),
        wh_atleast: "3840x2160".to_string(),
        wh_purity: "100".to_string(),
        wh_categories: "100".to_string(),
        wh_order: "desc".to_string(),
        wh_ratios: "16x9".to_string(),
        wh_sorting: "random".to_string(),
        wh_colors: String::new(),
        us_orientation: "landscape".to_string(),
        us_featured: String::new(),
    };
    let mut index = 0;
    while index < arguments.len() {
        let option = arguments[index].as_str();
        if option == "-h" || option == "--help" {
            sh::out_str(HELP);
            std::process::exit(0);
        }
        if option == "-f" || option == "--featured" {
            options.us_featured = "true".to_string();
            index += 1;
            continue;
        }
        let target = match option {
            "-S" | "--source" => &mut options.source,
            "-q" | "--query" => &mut options.query,
            "-l" | "--location" => &mut options.location,
            "-k" | "--apikey" => &mut options.apikey,
            "-C" | "--colors" => &mut options.wh_colors,
            "-a" | "--atleast" => &mut options.wh_atleast,
            "-p" | "--purity" => &mut options.wh_purity,
            "-c" | "--categories" => &mut options.wh_categories,
            "-r" | "--ratios" => &mut options.wh_ratios,
            "-s" | "--sorting" => &mut options.wh_sorting,
            "-O" | "--order" => &mut options.wh_order,
            "-o" | "--orientation" => &mut options.us_orientation,
            other => die(&format!("unknown option: {other}")),
        };
        // The original repeats forever when a value is missing (`shift 2`
        // fails and leaves argv untouched); the port treats it as an empty
        // value and consumes the option instead of hanging.
        if let Some(value) = arguments.get(index + 1) {
            *target = value.clone();
            index += 2;
        } else {
            *target = String::new();
            index += 1;
        }
    }
    options
}

/// `curl -fsS --retry 3 URL`, failing like the original's `|| die`.
fn api_request(url: &str, failure: &str) -> Vec<u8> {
    let output = std::process::Command::new("curl")
        .args(["-fsS", "--retry", "3", url])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    match output {
        Ok(output) if output.status.success() => output.stdout,
        _ => die(failure),
    }
}

fn download(image_url: &str, destination: &str) {
    // No `set -e` in the original: a failed download is not fatal, the
    // destination is still printed.
    let _ = std::process::Command::new("curl")
        .args(["-fsS", "--retry", "3", "-o", destination, image_url])
        .stdin(Stdio::null())
        .status();
}

fn download_wallhaven(options: &Options) -> ! {
    let key = if options.apikey.is_empty() {
        sh::env_nonempty("WALLHAVEN_API_KEY").unwrap_or_default()
    } else {
        options.apikey.clone()
    };

    let mut api_url = "https://wallhaven.cc/api/v1/search?".to_string();
    if !options.query.is_empty() {
        api_url.push_str("q=");
        api_url.push_str(&sh::percent_encode(&options.query));
    }
    if !options.wh_categories.is_empty() {
        api_url.push_str("&categories=");
        api_url.push_str(&options.wh_categories);
    }
    if !options.wh_purity.is_empty() {
        api_url.push_str("&purity=");
        api_url.push_str(&options.wh_purity);
    }
    if !options.wh_order.is_empty() {
        api_url.push_str("&order=");
        api_url.push_str(&options.wh_order);
    }
    if !options.wh_colors.is_empty() {
        api_url.push_str("&colors=");
        api_url.push_str(&options.wh_colors.replace('#', ""));
    }
    if !options.wh_ratios.is_empty() {
        api_url.push_str("&ratios=");
        api_url.push_str(&options.wh_ratios);
    }
    if !options.wh_atleast.is_empty() {
        api_url.push_str("&atleast=");
        api_url.push_str(&options.wh_atleast);
    }
    if !options.wh_sorting.is_empty() {
        api_url.push_str("&sorting=");
        api_url.push_str(&options.wh_sorting);
    }
    if !key.is_empty() {
        api_url.push_str("&apikey=");
        api_url.push_str(&key);
    }
    api_url.push_str(&format!("&page={}", random_below(10) + 1));

    let payload = api_request(&api_url, "Wallhaven API failed");
    let json: Value = serde_json::from_slice(&payload).unwrap_or(Value::Null);

    let mut paths: Vec<String> = Vec::new();
    for entry in sh::jq_iter_optional_field(&json, "data") {
        match sh::jq_index(&entry, "path") {
            Ok(value) => {
                for line in sh::jq_render(&value).split('\n') {
                    paths.push(line.to_string());
                }
            }
            // jq aborts the filter at the first "cannot index" error; the
            // values emitted before it are what mapfile saw.
            Err(()) => break,
        }
    }
    if paths.is_empty() {
        die("No wallpapers found on Wallhaven.");
    }

    let image = &paths[random_below(paths.len())];
    let _ = fs::create_dir_all(&options.location);
    let filename = image.rsplit('/').next().unwrap_or(image);
    let destination = format!("{}/{filename}", options.location);
    download(image, &destination);
    sh::out_str_line(&destination);
    std::process::exit(0);
}

fn unsplash_key(options: &Options) -> String {
    if !options.apikey.is_empty() {
        return options.apikey.clone();
    }
    if let Some(key) = sh::env_nonempty("UNSPLASH_ACCESS_KEY") {
        return key;
    }
    let key_path = Path::new(&sh::home()).join(".gemini/unsplash.key");
    if key_path.is_file() {
        if let Some(content) = sh::read_text(&key_path) {
            return content.trim_end_matches('\n').to_string();
        }
    }
    String::new()
}

/// `.urls.raw` / `.id` with jq's "array means first element" wrapper.
fn unsplash_field(json: &Value, path: &[&str]) -> Result<String, ()> {
    let target = if json.is_array() {
        json.get(0).cloned().unwrap_or(Value::Null)
    } else {
        json.clone()
    };
    let value = sh::jq_index_chain(&target, path)?;
    Ok(sh::jq_render(&value))
}

fn download_unsplash(options: &Options) -> ! {
    let key = unsplash_key(options);
    if key.is_empty() {
        die("Unsplash requires API Key (use -k, export UNSPLASH_ACCESS_KEY, or save to ~/.gemini/unsplash.key)");
    }

    let mut api_url = format!("https://api.unsplash.com/photos/random?client_id={key}&count=1");
    if !options.query.is_empty() {
        api_url.push_str("&query=");
        api_url.push_str(&sh::percent_encode(&options.query));
    }
    if !options.us_orientation.is_empty() {
        api_url.push_str("&orientation=");
        api_url.push_str(&options.us_orientation);
    }
    if !options.us_featured.is_empty() {
        api_url.push_str("&featured=true");
    }

    let payload = api_request(&api_url, "Unsplash API failed");
    let json: Value = serde_json::from_slice(&payload).unwrap_or(Value::Null);
    let image_url = unsplash_field(&json, &["urls", "raw"]).unwrap_or_default();
    let id = unsplash_field(&json, &["id"]).unwrap_or_default();

    if image_url == "null" || image_url.is_empty() {
        die("No image found on Unsplash.");
    }

    let _ = fs::create_dir_all(&options.location);
    let destination = format!("{}/unsplash-{id}.jpg", options.location);
    download(&image_url, &destination);
    sh::out_str_line(&destination);
    std::process::exit(0);
}

fn main() {
    sh::require(&prog(), "curl");
    // The port no longer runs jq, but the original refuses to start without
    // it; keeping the gate preserves the missing-dependency contract.
    sh::require(&prog(), "jq");
    let arguments = sh::args();
    let options = parse(&arguments);
    match options.source.as_str() {
        "wallhaven" => download_wallhaven(&options),
        "unsplash" => download_unsplash(&options),
        other => die(&format!("Unknown source: {other}")),
    }
}
