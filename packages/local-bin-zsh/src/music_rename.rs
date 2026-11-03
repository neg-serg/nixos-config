//! Rust port of `packages/local-bin/bin/music-rename`.
//!
//! Renames the album directory of a music file/directory to
//! `ARTIST-⟨YEAR⟩-ALBUM` (spaces become `·`, `/` becomes `-`) inside
//! `$XDG_MUSIC_DIR`, using the `albumdetails` output. The year goes through the
//! original conversion table; the exact table is reproduced as a range map,
//! including its 1890s quirk (`1890` -> `180`).
//!
//! `current` mode asks MPD over `nc` (or `socat`) for the current track, then
//! renames that track's directory. Metadata parsing (`rg`, `awk`, `cut`,
//! `sed`, `dirname`, `basename`) is native here; albumdetails/find/realpath/mv/
//! ren/rmdir/nc/socat are spawned with the original argv.

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};

use local_bin_zsh::{
    capture, dirname, err_str, first_fields, out_str, raw_args, replace_all, replace_byte, run,
    strip_trailing_newlines, trim, var, var_nonempty, which_str, Site, Stderr, Stdin, Stdout,
};

const USAGE: &str = include_str!("music_rename_usage.txt");

/// `lhs='-⟨'` / `rhs='⟩-'` from the original (U+27E8/U+27E9 in UTF-8).
const LHS: &[u8] = b"-\xE2\x9F\xA8";
const RHS: &[u8] = b"\xE2\x9F\xA9-";
/// The `·` the original substitutes for spaces (U+00B7).
const MIDDLE_DOT: &[u8] = b"\xC2\xB7";

const ALBUMDETAILS_LINE: u32 = 1;
const FIND_LINE: u32 = 2;
const REALPATH_LINE: u32 = 27;
const MV_LINE: u32 = 28;
const REN_LINE: u32 = 30;
const RMDIR_LINE: u32 = 31;
const NC_LINE: u32 = 20;
const SOCAT_LINE: u32 = 23;

/// `rg "^FIELD:" <<< "$Data" | cut -d ':' -f 2-`, with command-substitution
/// newline handling.
fn extract_field(data: &[u8], field: &[u8]) -> Vec<u8> {
    let mut prefix = field.to_vec();
    prefix.push(b':');
    let mut values: Vec<Vec<u8>> = Vec::new();
    for line in data.split(|byte| *byte == b'\n') {
        if line.starts_with(&prefix) {
            if let Some(position) = line.iter().position(|byte| *byte == b':') {
                values.push(line[position + 1..].to_vec());
            }
        }
    }
    let mut joined = Vec::new();
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            joined.push(b'\n');
        }
        joined.extend_from_slice(value);
    }
    strip_trailing_newlines(joined)
}

/// `conv_table[$year]` followed by `${year//$year/$conv_table[$year]}`.
///
/// The table is keyed by the four-digit strings built by `generate_convert_table`;
/// an absent key yields the empty string, which makes the caller skip the
/// rename. The 1890s arm is the original's `18$q` with `q` being the last
/// digit only, hence `1890 -> 180`.
fn convert_year(year: &[u8]) -> Vec<u8> {
    if year.len() != 4 || !year.iter().all(|byte| byte.is_ascii_digit()) {
        return Vec::new();
    }
    let digits = std::str::from_utf8(year).expect("digits are ASCII");
    let value: u32 = digits.parse().expect("four ASCII digits fit in u32");
    match value {
        1800..=1889 => year.to_vec(),
        1890..=1899 => format!("18{}", value - 1890).into_bytes(),
        1900..=1989 => format!("1x{:02}", value - 1900).into_bytes(),
        1990..=1999 => format!("1x{}", value - 1990).into_bytes(),
        2000 => b"2x0".to_vec(),
        2001..=2009 => format!("2x{}", value - 2000).into_bytes(),
        2010..=2035 => format!("2x{}", (b'A' + (value - 2010) as u8) as char).into_bytes(),
        _ => Vec::new(),
    }
}

fn is_directory(path: &OsStr) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_dir())
        .unwrap_or(false)
}

fn rename_files(paths: &[OsString]) -> i32 {
    let data = capture(
        Site::Func("rename_files", ALBUMDETAILS_LINE),
        "albumdetails",
        paths,
        Stdin::Inherit,
        Stderr::Inherit,
    )
    .text();
    rename(&data, paths.first().map(|path| path.as_os_str()))
}

fn rename_dir(path: &OsStr) -> i32 {
    if path.is_empty() {
        return 0;
    }
    let arguments = [
        path.to_os_string(),
        OsString::from("-exec"),
        OsString::from("albumdetails"),
        OsString::from("{}"),
        OsString::from("+"),
    ];
    let data = capture(
        Site::Func("rename_dir", FIND_LINE),
        "find",
        &arguments,
        Stdin::Inherit,
        Stderr::Null,
    )
    .text();
    rename(&data, Some(path))
}

fn rename(data: &[u8], source: Option<&OsStr>) -> i32 {
    let artist = extract_field(data, b"Artist");
    let year = extract_field(data, b"Year");
    let album = extract_field(data, b"Album");

    let year = convert_year(&first_fields(&year));
    let album = replace_all(&album, b"/", b"-");
    let artist = replace_all(&artist, b"/", b"-");

    let src = match source {
        Some(value) if is_directory(value) => value.as_bytes().to_vec(),
        Some(value) => dirname(value.as_bytes()),
        None => dirname(b""),
    };

    let artist = trim(&artist).to_vec();
    let album = trim(&album).to_vec();
    let year = trim(&year).to_vec();

    if artist.is_empty() || year.is_empty() || album.is_empty() {
        return 0;
    }

    let music_dir = var("XDG_MUSIC_DIR");
    let mut name = Vec::new();
    name.extend_from_slice(&artist);
    name.extend_from_slice(LHS);
    name.extend_from_slice(&year);
    name.extend_from_slice(RHS);
    name.extend_from_slice(&album);
    let dotted = replace_byte(&name, b' ', MIDDLE_DOT);
    let base = local_bin_zsh::basename(&dotted);

    let mut result = music_dir.as_bytes().to_vec();
    result.push(b'/');
    result.extend_from_slice(&base);
    let result = OsString::from_vec(result);
    let src = OsString::from_vec(src);

    let source_real = capture(
        Site::Func("rename", REALPATH_LINE),
        "realpath",
        &[OsString::from("-m"), OsString::from("--"), src.clone()],
        Stdin::Null,
        Stderr::Inherit,
    )
    .text();
    let result_real = capture(
        Site::Func("rename", REALPATH_LINE),
        "realpath",
        &[OsString::from("-m"), OsString::from("--"), result.clone()],
        Stdin::Null,
        Stderr::Inherit,
    )
    .text();

    if source_real != result_real {
        run(
            Site::Func("rename", MV_LINE),
            "mv",
            &[
                OsString::from("-i"),
                OsString::from("--"),
                src.clone(),
                result.clone(),
            ],
            Stdin::Inherit,
            Stdout::Inherit,
            Stderr::Inherit,
        );
    }
    run(
        Site::Func("rename", REN_LINE),
        "ren",
        &[OsString::from("-i"), OsString::from("--"), result],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Inherit,
    );
    // `rmdir -- "$src" 2>/dev/null || true`
    run(
        Site::Func("rename", RMDIR_LINE),
        "rmdir",
        &[OsString::from("--"), src],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Null,
    );
    0
}

/// `_current_file_path`: MPD's `currentsong` over nc/socat, first `file:` line.
fn current_file_path() -> Option<Vec<u8>> {
    let host = var_nonempty("MPD_HOST").unwrap_or_else(|| OsString::from("localhost"));
    let port = var_nonempty("MPD_PORT").unwrap_or_else(|| OsString::from("6600"));
    let host_bytes = host.as_bytes();
    let (password, host) = match host_bytes.iter().position(|byte| *byte == b'@') {
        Some(position) => (
            host_bytes[..position].to_vec(),
            host_bytes[position + 1..].to_vec(),
        ),
        None => (Vec::new(), host_bytes.to_vec()),
    };
    let host = OsString::from_vec(host);

    let mut payload = Vec::new();
    if !password.is_empty() {
        payload.extend_from_slice(b"password ");
        payload.extend_from_slice(&password);
        payload.push(b'\n');
    }
    payload.extend_from_slice(b"currentsong\nclose\n");
    // `print -r -- "$payload"` adds the newline the here-string-free shell
    // pipeline sends to nc/socat.
    payload.push(b'\n');

    let output = if which_str("nc").is_some() {
        capture(
            Site::Func("_current_file_path", NC_LINE),
            "nc",
            &[OsString::from("-w"), OsString::from("1"), host, port],
            Stdin::Bytes(payload),
            Stderr::Inherit,
        )
        .stdout
    } else if which_str("socat").is_some() {
        let mut target = b"TCP:".to_vec();
        target.extend_from_slice(host.as_bytes());
        target.push(b':');
        target.extend_from_slice(port.as_bytes());
        target.extend_from_slice(b",connect-timeout=1");
        capture(
            Site::Func("_current_file_path", SOCAT_LINE),
            "socat",
            &[OsString::from("-"), OsString::from_vec(target)],
            Stdin::Bytes(payload),
            Stderr::Inherit,
        )
        .stdout
    } else {
        err_str("Neither nc nor socat found\n");
        return None;
    };

    for line in output.split(|byte| *byte == b'\n') {
        if let Some(path) = line.strip_prefix(b"file: ") {
            return Some(path.to_vec());
        }
    }
    None
}

fn current_mode() -> i32 {
    let current = match current_file_path() {
        Some(current) if !current.is_empty() => current,
        _ => {
            err_str("No current track from MPD\n");
            return 1;
        }
    };
    let music_dir = var("XDG_MUSIC_DIR");
    let mut directory = music_dir.as_bytes().to_vec();
    directory.push(b'/');
    directory.extend_from_slice(&dirname(&current));
    rename_dir(OsStr::from_bytes(&directory))
}

fn main() {
    let arguments = raw_args();
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"-h" | b"--help") {
            out_str(USAGE);
            return;
        }
    }

    // `[[ -z "${1// }" ]] && exit 0`: no argument (or only spaces) is a no-op.
    let first = arguments
        .first()
        .map(|value| value.as_bytes())
        .unwrap_or(b"");
    if first.iter().all(|byte| *byte == b' ') {
        std::process::exit(0);
    }

    let status = match first.first() {
        Some(b'c') => current_mode(),
        Some(b'f') => rename_files(&arguments[1..]),
        _ => {
            let mut status = 0;
            for argument in &arguments {
                status = rename_dir(argument.as_os_str());
            }
            status
        }
    };
    std::process::exit(status);
}
