//! Type-directed scanners.
//!
//! These are the part that makes `tint` work on programs nobody wrote rules
//! for: instead of a per-tool regex zoo it classifies *tokens* — a size, a
//! percentage, an address, a path, a timestamp — and colours the class. A new
//! CLI then gets useful colouring for free, and a ruleset only has to add the
//! handful of words that are specific to it.
//!
//! Everything is byte-oriented and allocation-free: no regex compilation at
//! startup, no per-line allocation beyond the shared hit vector.

use std::collections::HashMap;
use std::sync::OnceLock;

use crate::hit::Hit;
use crate::theme::Kind;

/// Priorities. Rules live at and above [`PRIO_RULE`]; scanners stay below so a
/// ruleset can always override a classifier for its own output.
pub const PRIO_STRUCT: u16 = 90;
pub const PRIO_TIME: u16 = 100;
pub const PRIO_STR: u16 = 105;
pub const PRIO_PATH: u16 = 108;
pub const PRIO_NUM: u16 = 110;
pub const PRIO_ADDR: u16 = 112;
pub const PRIO_URL: u16 = 115;
pub const PRIO_KEYWORD: u16 = 120;
pub const PRIO_KEY: u16 = 130;
pub const PRIO_HEADER: u16 = 300;
pub const PRIO_RULE: u16 = 400;

/// Which scanner groups are active for a ruleset.
#[derive(Clone, Copy, Debug)]
pub struct ScanCfg {
    pub numbers: bool,
    pub sizes: bool,
    pub percents: bool,
    pub durations: bool,
    pub temps: bool,
    pub ips: bool,
    pub macs: bool,
    pub paths: bool,
    pub urls: bool,
    pub times: bool,
    pub hashes: bool,
    pub strings: bool,
    pub keywords: bool,
    pub keyval: bool,
    pub structure: bool,
    pub headers: bool,
    pub ports: bool,
}

impl Default for ScanCfg {
    fn default() -> ScanCfg {
        ScanCfg {
            numbers: false,
            sizes: true,
            percents: true,
            durations: true,
            temps: true,
            ips: true,
            macs: true,
            paths: true,
            urls: true,
            times: true,
            hashes: true,
            strings: true,
            keywords: true,
            keyval: true,
            structure: true,
            headers: false,
            ports: false,
        }
    }
}

/// Percent thresholds: below `MID` is fine, below `HIGH` is worth a look.
const PCT_MID: f64 = 70.0;
const PCT_HIGH: f64 = 90.0;
/// Temperature thresholds in degrees Celsius.
const TEMP_HOT: f64 = 80.0;

/// Scan one line (without its terminator) and append the hits it finds.
pub fn scan(line: &[u8], cfg: &ScanCfg, out: &mut Vec<Hit>) {
    if cfg.headers && looks_like_header(line) {
        let start = line
            .iter()
            .position(|b| !b.is_ascii_whitespace())
            .unwrap_or(0);
        out.push(Hit::new(start, line.len(), Kind::Hdr, PRIO_HEADER));
        return;
    }
    let n = line.len();
    let mut i = 0;
    while i < n {
        let b = line[i];
        i = match b {
            0x1b => skip_escape(line, i),
            b'0'..=b'9' => scan_numeric(line, i, cfg, out).unwrap_or(i + 1),
            b'a'..=b'z' | b'A'..=b'Z' | b'_' => scan_word(line, i, cfg, out).unwrap_or(i + 1),
            b'"' | b'\'' => scan_string(line, i, cfg, out).unwrap_or(i + 1),
            b'/' => scan_path(line, i, cfg, out).unwrap_or(i + 1),
            b'~' | b'.' if line.get(i + 1) == Some(&b'/') => {
                scan_path(line, i, cfg, out).unwrap_or(i + 1)
            }
            b'|' => {
                if cfg.structure {
                    out.push(Hit::new(i, i + 1, Kind::Sep, PRIO_STRUCT));
                }
                i + 1
            }
            b'-' if line.get(i + 1) == Some(&b'>') => {
                if cfg.structure {
                    out.push(Hit::new(i, i + 2, Kind::Sep, PRIO_STRUCT));
                }
                i + 2
            }
            b'=' if line.get(i + 1) == Some(&b'>') => {
                if cfg.structure {
                    out.push(Hit::new(i, i + 2, Kind::Sep, PRIO_STRUCT));
                }
                i + 2
            }
            b':' => {
                // `::1` and `fe80::` start with a colon, so addresses are tried
                // before the `::` punctuation rule.
                if cfg.ips {
                    if let Some(end) = try_ipv6(line, i) {
                        out.push(Hit::new(i, end, Kind::Ip, PRIO_ADDR));
                        i = end;
                        continue;
                    }
                }
                if cfg.structure && line.get(i + 1) == Some(&b':') {
                    out.push(Hit::new(i, i + 2, Kind::Sep, PRIO_STRUCT));
                    i + 2
                } else {
                    i + 1
                }
            }
            _ => i + 1,
        };
    }
}

/// Skip an ANSI escape sequence so its payload bytes are not re-classified.
fn skip_escape(line: &[u8], i: usize) -> usize {
    let n = line.len();
    match line.get(i + 1) {
        Some(b'[') => {
            let mut j = i + 2;
            while j < n {
                let b = line[j];
                j += 1;
                if (0x40..=0x7e).contains(&b) {
                    return j;
                }
            }
            n
        }
        Some(b']') => {
            let mut j = i + 2;
            while j < n {
                if line[j] == 0x07 {
                    return j + 1;
                }
                if line[j] == 0x1b && line.get(j + 1) == Some(&b'\\') {
                    return j + 2;
                }
                j += 1;
            }
            n
        }
        Some(_) => (i + 2).min(n),
        None => n,
    }
}

fn is_hex(b: u8) -> bool {
    b.is_ascii_hexdigit()
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn word_end(line: &[u8], start: usize) -> usize {
    let mut j = start;
    while j < line.len() && is_word_byte(line[j]) {
        j += 1;
    }
    j
}

fn boundary_before(line: &[u8], i: usize) -> bool {
    i == 0 || !is_word_byte(line[i - 1])
}

fn boundary_after(line: &[u8], j: usize) -> bool {
    j >= line.len() || !is_word_byte(line[j])
}

/// Read `[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?`, returning the end index.
fn read_number(line: &[u8], start: usize) -> usize {
    let n = line.len();
    let mut j = start;
    while j < n && line[j].is_ascii_digit() {
        j += 1;
    }
    if j + 1 < n && line[j] == b'.' && line[j + 1].is_ascii_digit() {
        j += 1;
        while j < n && line[j].is_ascii_digit() {
            j += 1;
        }
    }
    if j < n && (line[j] == b'e' || line[j] == b'E') {
        let mut k = j + 1;
        if k < n && (line[k] == b'+' || line[k] == b'-') {
            k += 1;
        }
        if k < n && line[k].is_ascii_digit() {
            while k < n && line[k].is_ascii_digit() {
                k += 1;
            }
            j = k;
        }
    }
    j
}

fn parse_f64(line: &[u8], start: usize, end: usize) -> f64 {
    std::str::from_utf8(&line[start..end])
        .ok()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0)
}

/// Numbers, and every token that starts with a digit.
fn scan_numeric(line: &[u8], i: usize, cfg: &ScanCfg, out: &mut Vec<Hit>) -> Option<usize> {
    if cfg.times {
        if let Some(end) = try_iso_time(line, i) {
            out.push(Hit::new(i, end, Kind::Time, PRIO_TIME));
            return Some(end);
        }
        if let Some(end) = try_clock(line, i) {
            out.push(Hit::new(i, end, Kind::Time, PRIO_TIME));
            return Some(end);
        }
    }
    if cfg.ips {
        if let Some(end) = try_ipv4(line, i) {
            out.push(Hit::new(i, end, Kind::Ip, PRIO_ADDR));
            return Some(end);
        }
    }
    if cfg.macs {
        if let Some(end) = try_mac(line, i) {
            out.push(Hit::new(i, end, Kind::Mac, PRIO_ADDR));
            return Some(end);
        }
    }
    if cfg.ips {
        if let Some(end) = try_ipv6(line, i) {
            out.push(Hit::new(i, end, Kind::Ip, PRIO_ADDR));
            return Some(end);
        }
    }
    if cfg.hashes && boundary_before(line, i) {
        if let Some(end) = try_hex(line, i) {
            out.push(Hit::new(i, end, Kind::Hash, PRIO_NUM));
            return Some(end);
        }
    }
    let num_end = read_number(line, i);
    if cfg.percents && line.get(num_end) == Some(&b'%') {
        let v = parse_f64(line, i, num_end);
        let kind = if v >= PCT_HIGH {
            Kind::PctHigh
        } else if v >= PCT_MID {
            Kind::PctMid
        } else {
            Kind::PctLow
        };
        out.push(Hit::new(i, num_end, kind, PRIO_NUM));
        out.push(Hit::new(num_end, num_end + 1, Kind::Unit, PRIO_NUM));
        return Some(num_end + 1);
    }
    if cfg.durations {
        if let Some(end) = try_duration(line, num_end) {
            out.push(Hit::new(i, end, Kind::Dur, PRIO_NUM));
            return Some(end);
        }
    }
    if cfg.sizes {
        if let Some(end) = try_size(line, num_end) {
            out.push(Hit::new(i, end, Kind::Size, PRIO_NUM));
            return Some(end);
        }
    }
    if cfg.temps {
        if let Some(end) = try_temp(line, num_end) {
            let v = parse_f64(line, i, num_end);
            let kind = if v >= TEMP_HOT {
                Kind::TempHot
            } else {
                Kind::TempCool
            };
            out.push(Hit::new(i, end, kind, PRIO_NUM));
            return Some(end);
        }
    }
    if cfg.ports && i >= 2 && line[i - 1] == b':' && !line[i - 2].is_ascii_whitespace() {
        // `host:22`, `[::1]:443`: a port, not a table number.
        out.push(Hit::new(i, num_end, Kind::Port, PRIO_NUM));
        return Some(num_end);
    }
    if cfg.numbers {
        out.push(Hit::new(i, num_end, Kind::Num, PRIO_NUM));
    }
    Some(num_end)
}

/// `2026-10-21`, `2026-10-21T12:48:33.123Z`, `2026-10-21 12:48:33`.
fn try_iso_time(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    if i + 10 > n || !boundary_before(line, i) {
        return None;
    }
    let digits = |from: usize, count: usize| -> bool {
        from + count <= n && line[from..from + count].iter().all(u8::is_ascii_digit)
    };
    if !(digits(i, 4)
        && line[i + 4] == b'-'
        && digits(i + 5, 2)
        && line[i + 7] == b'-'
        && digits(i + 8, 2))
    {
        return None;
    }
    let mut j = i + 10;
    let sep = line.get(j).copied();
    if sep == Some(b'T') || sep == Some(b' ') {
        if digits(j + 1, 2) && line.get(j + 3) == Some(&b':') && digits(j + 4, 2) {
            j += 6;
            if line.get(j) == Some(&b':') && digits(j + 1, 2) {
                j += 3;
            }
            if line.get(j) == Some(&b'.') {
                let mut k = j + 1;
                while k < n && line[k].is_ascii_digit() {
                    k += 1;
                }
                if k > j + 1 {
                    j = k;
                }
            }
            if matches!(line.get(j), Some(b'Z') | Some(b'z')) {
                j += 1;
            }
        }
    }
    if !boundary_after(line, j) {
        return None;
    }
    Some(j)
}

/// `12:48:33` (and `12:48`).
fn try_clock(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    if !boundary_before(line, i) {
        return None;
    }
    let digits = |from: usize, count: usize| -> bool {
        from + count <= n && line[from..from + count].iter().all(u8::is_ascii_digit)
    };
    let mut j = i;
    let mut groups = 0;
    loop {
        if !digits(j, 2) {
            return None;
        }
        let value = parse_f64(line, j, j + 2) as u32;
        if value > 59 {
            return None;
        }
        j += 2;
        groups += 1;
        if groups == 3 || line.get(j) != Some(&b':') {
            break;
        }
        j += 1;
    }
    if groups < 2 || !boundary_after(line, j) {
        return None;
    }
    Some(j)
}

fn try_ipv4(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    if !boundary_before(line, i) {
        return None;
    }
    let mut j = i;
    for octet in 0..4 {
        let start = j;
        while j < n && line[j].is_ascii_digit() && j - start < 3 {
            j += 1;
        }
        if j == start {
            return None;
        }
        let value = parse_f64(line, start, j) as u32;
        if value > 255 {
            return None;
        }
        if octet < 3 {
            if line.get(j) != Some(&b'.') {
                return None;
            }
            j += 1;
        }
    }
    if line.get(j) == Some(&b'/') {
        let mut k = j + 1;
        while k < n && line[k].is_ascii_digit() {
            k += 1;
        }
        if k > j + 1 {
            let prefix = parse_f64(line, j + 1, k) as u32;
            if prefix <= 128 {
                j = k;
            }
        }
    }
    if !boundary_after(line, j) {
        return None;
    }
    Some(j)
}

fn try_mac(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    if !boundary_before(line, i) {
        return None;
    }
    let mut j = i;
    for group in 0..6 {
        if j + 2 > n || !line[j..j + 2].iter().all(|b| is_hex(*b)) {
            return None;
        }
        j += 2;
        if group < 5 {
            if line.get(j) != Some(&b':') {
                return None;
            }
            j += 1;
        }
    }
    if !boundary_after(line, j) {
        return None;
    }
    Some(j)
}

fn try_ipv6(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    if !boundary_before(line, i) {
        return None;
    }
    let mut j = i;
    let mut colons = 0;
    let mut groups = 0;
    let mut group_len = 0;
    while j < n {
        let b = line[j];
        if is_hex(b) {
            group_len += 1;
            if group_len > 4 {
                return None;
            }
            j += 1;
        } else if b == b':' {
            if group_len > 0 {
                groups += 1;
            }
            group_len = 0;
            colons += 1;
            if colons > 7 {
                return None;
            }
            j += 1;
        } else {
            break;
        }
    }
    if group_len > 0 {
        groups += 1;
    }
    // Two colons at least. Three groups is the comfortable case; shorter forms
    // (`::1`, `fe80::`) need the double colon to be sure and not eat `std::x`.
    let starts_double = line[i..].starts_with(b"::");
    let ends_double = colons >= 2 && line[..j].ends_with(b"::");
    let solid = groups >= 3 || (colons >= 2 && (starts_double || ends_double) && groups >= 1);
    if colons < 2 || !solid {
        return None;
    }
    // A CIDR prefix may follow: `fe80::1ff:fe23/64`.
    if line.get(j) == Some(&b'/') {
        let mut k = j + 1;
        while k < n && line[k].is_ascii_digit() && k - j <= 3 {
            k += 1;
        }
        if k > j + 1 && parse_f64(line, j + 1, k) as u32 <= 128 {
            j = k;
        }
    }
    if !boundary_after(line, j) {
        return None;
    }
    Some(j)
}

fn try_hex(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    let mut j = i;
    while j < n && is_hex(line[j]) && j - i <= 40 {
        j += 1;
    }
    let len = j - i;
    if !(7..=40).contains(&len) || !boundary_after(line, j) {
        return None;
    }
    // Require at least one digit: `frontend` is not an object id.
    if !line[i..j].iter().any(u8::is_ascii_digit) {
        return None;
    }
    Some(j)
}

fn try_duration(line: &[u8], start: usize) -> Option<usize> {
    const UNITS: [&[u8]; 8] = [b"ns", b"us", b"\xc2\xb5s", b"ms", b"s", b"m", b"h", b"d"];
    for unit in UNITS {
        if line.len() >= start + unit.len() && &line[start..start + unit.len()] == unit {
            let end = start + unit.len();
            if boundary_after(line, end) {
                return Some(end);
            }
        }
    }
    None
}

fn try_size(line: &[u8], start: usize) -> Option<usize> {
    // A single space between number and unit is common in `df -h`.
    let mut j = start;
    if line.get(j) == Some(&b' ') {
        j += 1;
    }
    let mut end = match line.get(j) {
        Some(b'K' | b'k' | b'M' | b'G' | b'T' | b'P' | b'E') => {
            let mut end = j + 1;
            if line.get(end) == Some(&b'i') {
                end += 1;
            }
            if matches!(line.get(end), Some(b'B') | Some(b'b')) {
                end += 1;
            }
            end
        }
        Some(b'B') => j + 1,
        _ => return None,
    };
    if !boundary_after(line, end) {
        return None;
    }
    Some(end)
}

fn try_temp(line: &[u8], start: usize) -> Option<usize> {
    // `<n>°C` / `<n>°F`
    if line.len() >= start + 3 && &line[start..start + 2] == b"\xc2\xb0" {
        let unit = line[start + 2];
        if unit == b'C' || unit == b'F' {
            let end = start + 3;
            if boundary_after(line, end) {
                return Some(end);
            }
        }
    }
    None
}

/// Words, addresses with letters, URLs, syslog timestamps.
fn scan_word(line: &[u8], i: usize, cfg: &ScanCfg, out: &mut Vec<Hit>) -> Option<usize> {
    if cfg.urls && boundary_before(line, i) {
        if let Some(end) = try_url(line, i) {
            out.push(Hit::new(i, end, Kind::Url, PRIO_URL));
            return Some(end);
        }
    }
    if cfg.times && boundary_before(line, i) {
        if let Some(end) = try_syslog_time(line, i) {
            out.push(Hit::new(i, end, Kind::Time, PRIO_TIME));
            return Some(end);
        }
    }
    // IPv6 and MAC addresses may start with a hex letter (`fe80::1`, `aa:bb:..`),
    // so they are tried here as well as on the numeric path.
    if cfg.macs && boundary_before(line, i) {
        if let Some(end) = try_mac(line, i) {
            out.push(Hit::new(i, end, Kind::Mac, PRIO_ADDR));
            return Some(end);
        }
    }
    if cfg.ips && boundary_before(line, i) {
        if let Some(end) = try_ipv6(line, i) {
            out.push(Hit::new(i, end, Kind::Ip, PRIO_ADDR));
            return Some(end);
        }
    }
    let end = word_end(line, i);
    if cfg.hashes && boundary_before(line, i) {
        if let Some(hex_end) = try_hex(line, i) {
            out.push(Hit::new(i, hex_end, Kind::Hash, PRIO_NUM));
            return Some(hex_end);
        }
    }
    let separator = if looks_like_key(&line[i..end]) {
        key_separator(line, end)
    } else {
        None
    };
    // `key=` is an assignment: colour the key. `word:` may just be a severity
    // label (`ERROR: boom`), so known keywords win there.
    if cfg.keyval && separator == Some(b'=') {
        out.push(Hit::new(i, end, Kind::Key, PRIO_KEY));
    } else if cfg.keywords && keyword(&line[i..end]).is_some() {
        out.push(Hit::new(
            i,
            end,
            keyword(&line[i..end]).unwrap(),
            PRIO_KEYWORD,
        ));
    } else if cfg.keyval && separator == Some(b':') {
        out.push(Hit::new(i, end, Kind::Key, PRIO_KEY));
    }
    if end == i {
        return Some(i + 1);
    }
    Some(end)
}

/// `key=` or `key:` introduces a value; `==`, `::` and `://` do not.
fn looks_like_key(word: &[u8]) -> bool {
    if word.is_empty() || word.len() > 24 {
        return false;
    }
    // `ValueError:` and `Address:Port` are not keys; `valid_lft:` and `state:`
    // are. Keys are lower-case, or carry an underscore/dot, or are all caps
    // (environment variable dumps).
    let has_upper = word.iter().any(u8::is_ascii_uppercase);
    let has_lower = word.iter().any(u8::is_ascii_lowercase);
    let shape = word.iter().any(|b| matches!(b, b'_' | b'.' | b'-'));
    !has_upper || !has_lower || shape
}

fn key_separator(line: &[u8], end: usize) -> Option<u8> {
    match line.get(end) {
        Some(b'=') if line.get(end + 1) != Some(&b'=') => Some(b'='),
        Some(b':') if matches!(line.get(end + 1), None | Some(b' ') | Some(b'\t')) => Some(b':'),
        _ => None,
    }
}

fn try_url(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    let mut j = i;
    if j >= n || !line[j].is_ascii_alphabetic() {
        return None;
    }
    while j < n && (line[j].is_ascii_alphanumeric() || matches!(line[j], b'+' | b'-' | b'.')) {
        j += 1;
    }
    if line.len() < j + 3 || &line[j..j + 3] != b"://" {
        return None;
    }
    j += 3;
    let payload = j;
    while j < n {
        let b = line[j];
        if b.is_ascii_whitespace()
            || matches!(
                b,
                b'"' | b'\'' | b'<' | b'>' | b')' | b']' | b'}' | b',' | b';'
            )
        {
            break;
        }
        j += 1;
    }
    if j == payload {
        return None;
    }
    Some(j)
}

/// Syslog style `Oct 21 12:48:33`.
fn try_syslog_time(line: &[u8], i: usize) -> Option<usize> {
    const MONTHS: [&[u8]; 12] = [
        b"Jan", b"Feb", b"Mar", b"Apr", b"May", b"Jun", b"Jul", b"Aug", b"Sep", b"Oct", b"Nov",
        b"Dec",
    ];
    let n = line.len();
    if i + 15 > n {
        return None;
    }
    if !MONTHS.iter().any(|m| &line[i..i + 3] == *m) {
        return None;
    }
    if line[i + 3] != b' ' {
        return None;
    }
    let mut j = i + 4;
    if line.get(j) == Some(&b' ') {
        j += 1;
    }
    let day_start = j;
    while j < n && line[j].is_ascii_digit() {
        j += 1;
    }
    if j == day_start || j - day_start > 2 || line.get(j) != Some(&b' ') {
        return None;
    }
    j += 1;
    let clock = try_clock(line, j)?;
    Some(clock)
}

fn scan_string(line: &[u8], i: usize, cfg: &ScanCfg, out: &mut Vec<Hit>) -> Option<usize> {
    if !cfg.strings {
        return None;
    }
    let quote = line[i];
    let mut j = i + 1;
    while j < line.len() && j - i < 512 {
        match line[j] {
            b'\\' => j += 2,
            b if b == quote => {
                if j > i + 1 {
                    out.push(Hit::new(i + 1, j, Kind::Str, PRIO_STR));
                }
                return Some(j + 1);
            }
            _ => j += 1,
        }
    }
    None
}

fn scan_path(line: &[u8], i: usize, cfg: &ScanCfg, out: &mut Vec<Hit>) -> Option<usize> {
    if !cfg.paths {
        return None;
    }
    // `/` must start a token: `1/2` and `and/or` are not paths.
    if !boundary_before(line, i) {
        return None;
    }
    if i > 0 {
        let prev = line[i - 1];
        if !matches!(
            prev,
            b' ' | b'\t' | b'(' | b'[' | b'"' | b'\'' | b'=' | b':' | b',' | b'|' | b'>' | b';'
        ) {
            return None;
        }
    }
    let n = line.len();
    let mut j = i;
    while j < n {
        let b = line[j];
        let ok = b.is_ascii_alphanumeric()
            || matches!(b, b'/' | b'.' | b'-' | b'_' | b'~' | b'+' | b'@' | b'%');
        if !ok {
            break;
        }
        j += 1;
    }
    while j > i + 1 && matches!(line[j - 1], b'.' | b'-' | b'/' | b'%' | b'@') {
        j -= 1;
    }
    if j - i < 2 {
        return None;
    }
    // A lone `/x` is more likely a division or a flag; require a directory-ish
    // shape (a second slash, a dot-suffix, or a tilde) to be sure.
    let slice = &line[i..j];
    let solid = slice.iter().skip(1).filter(|b| **b == b'/').count() >= 1
        || slice.contains(&b'.')
        || slice[0] == b'~'
        || slice.len() > 4;
    if !solid {
        return None;
    }
    out.push(Hit::new(i, j, Kind::Path, PRIO_PATH));
    Some(j)
}

/// Table header: no digits before the first column gap, at least two multi-space
/// gaps, mostly words. Dmesg-like lines start with `[` and are excluded.
fn looks_like_header(line: &[u8]) -> bool {
    let trimmed = match line.iter().position(|b| !b.is_ascii_whitespace()) {
        Some(pos) => &line[pos..],
        None => return false,
    };
    if trimmed.is_empty() || !trimmed[0].is_ascii_alphabetic() {
        return false;
    }
    let mut gaps = 0;
    let mut i = 0;
    while i + 1 < trimmed.len() {
        if trimmed[i] == b' ' && trimmed[i + 1] == b' ' {
            gaps += 1;
            while i < trimmed.len() && trimmed[i] == b' ' {
                i += 1;
            }
            continue;
        }
        i += 1;
    }
    if gaps < 2 {
        return false;
    }
    // Any digit in the line makes a header unlikely (values are numeric).
    !trimmed.iter().any(u8::is_ascii_digit)
}

/// Keyword table, built once. Words are matched lower-cased.
fn keywords() -> &'static HashMap<&'static str, Kind> {
    static TABLE: OnceLock<HashMap<&'static str, Kind>> = OnceLock::new();
    TABLE.get_or_init(|| {
        let mut map = HashMap::with_capacity(96);
        let mut add = |words: &[&'static str], kind: Kind| {
            for w in words {
                map.insert(*w, kind);
            }
        };
        add(
            &[
                "error",
                "errors",
                "err",
                "failed",
                "failure",
                "fail",
                "fatal",
                "critical",
                "panic",
                "denied",
                "refused",
                "unreachable",
                "timeout",
                "timed",
                "abort",
                "aborted",
                "segfault",
                "corrupt",
                "corrupted",
                "broken",
                "invalid",
                "missing",
                "cannot",
                "unable",
                "exceeded",
                "overflow",
                "killed",
                "died",
                "crash",
                "crashed",
            ],
            Kind::Err,
        );
        add(
            &[
                "warn",
                "warning",
                "warnings",
                "deprecated",
                "degraded",
                "retry",
                "retrying",
                "retries",
                "slow",
                "suspicious",
                "flaky",
                "stale",
                "expired",
                "dirty",
                "degraded:",
            ],
            Kind::Warn,
        );
        add(
            &[
                "ok",
                "success",
                "successful",
                "succeeded",
                "done",
                "active",
                "running",
                "enabled",
                "connected",
                "established",
                "passed",
                "pass",
                "ready",
                "listening",
                "true",
                "yes",
                "found",
                "alive",
                "healthy",
                "online",
                "up",
                "loaded",
                "mounted",
                "available",
            ],
            Kind::Ok,
        );
        add(
            &[
                "info",
                "information",
                "notice",
                "started",
                "starting",
                "stopped",
                "stopping",
                "loading",
                "mounting",
                "created",
                "creating",
                "built",
                "building",
                "copying",
                "running:",
                "phase",
            ],
            Kind::Info,
        );
        add(
            &[
                "note",
                "hint",
                "changed",
                "modified",
                "reached",
                "searched",
                "skipped",
                "already",
                "unchanged",
                "unmodified",
                "up-to-date",
                "cached",
            ],
            Kind::Note,
        );
        add(
            &[
                "debug",
                "trace",
                "verbose",
                "null",
                "none",
                "nil",
                "undefined",
                "nan",
            ],
            Kind::Dim,
        );
        add(
            &[
                "no",
                "false",
                "off",
                "disabled",
                "inactive",
                "dead",
                "down",
                "stopped:",
                "unmounted",
                "unreachable:",
                "deprecated:",
            ],
            Kind::Warn,
        );
        map
    })
}

/// Look up a word in the keyword table (case-insensitive).
fn keyword(word: &[u8]) -> Option<Kind> {
    const MAX: usize = 24;
    if word.is_empty() || word.len() > MAX || !word.is_ascii() {
        return None;
    }
    let mut buf = [0u8; MAX];
    for (dst, src) in buf.iter_mut().zip(word.iter()) {
        *dst = src.to_ascii_lowercase();
    }
    let lower = std::str::from_utf8(&buf[..word.len()]).ok()?;
    keywords().get(lower).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hits(line: &str, cfg: &ScanCfg) -> Vec<(usize, usize, Kind)> {
        let mut out = Vec::new();
        scan(line.as_bytes(), cfg, &mut out);
        crate::hit::normalize(&mut out);
        out.iter()
            .map(|h| (h.start as usize, h.end as usize, h.kind))
            .collect()
    }

    fn find(line: &str, kind: Kind) -> Vec<String> {
        let cfg = ScanCfg::default();
        hits(line, &cfg)
            .into_iter()
            .filter(|(_, _, k)| *k == kind)
            .map(|(s, e, _)| line[s..e].to_string())
            .collect()
    }

    #[test]
    fn ipv4_and_cidr() {
        assert_eq!(
            find("inet 192.168.1.5/24 brd", Kind::Ip),
            ["192.168.1.5/24"]
        );
        assert_eq!(find("addr 10.0.0.1:8080", Kind::Ip), ["10.0.0.1"]);
    }

    #[test]
    fn ipv6_and_mac() {
        assert_eq!(
            find("inet6 fe80::1ff:fe23/64 scope", Kind::Ip),
            ["fe80::1ff:fe23/64"]
        );
        assert_eq!(
            find("link aa:bb:cc:dd:ee:ff state", Kind::Mac),
            ["aa:bb:cc:dd:ee:ff"]
        );
    }

    #[test]
    fn sizes_percents_durations() {
        assert_eq!(
            find("root 12G 4.5GiB 512K", Kind::Size),
            ["12G", "4.5GiB", "512K"]
        );
        assert_eq!(find("Use% 43% 95%", Kind::PctLow), ["43"]);
        assert_eq!(find("Use% 95%", Kind::PctHigh), ["95"]);
        assert_eq!(find("took 230ms then 1.5s", Kind::Dur), ["230ms", "1.5s"]);
    }

    #[test]
    fn timestamps() {
        assert_eq!(
            find("2026-10-21T12:48:33.123Z hello", Kind::Time),
            ["2026-10-21T12:48:33.123Z"]
        );
        assert_eq!(
            find("Oct 21 12:48:33 trantor", Kind::Time),
            ["Oct 21 12:48:33"]
        );
        assert_eq!(find("at 12:48:33 ok", Kind::Time), ["12:48:33"]);
    }

    #[test]
    fn paths_and_urls() {
        assert_eq!(
            find("open /etc/nixos/flake.nix now", Kind::Path),
            ["/etc/nixos/flake.nix"]
        );
        assert_eq!(
            find("see https://example.com/x?y=1 ok", Kind::Url),
            ["https://example.com/x?y=1"]
        );
        assert!(find("no path 1/2 here", Kind::Path).is_empty());
    }

    #[test]
    fn keywords_are_case_insensitive() {
        assert_eq!(find("ERROR: boom", Kind::Err), ["ERROR"]);
        assert_eq!(find("Error: boom", Kind::Err), ["Error"]);
        assert_eq!(find("status ok", Kind::Ok), ["ok"]);
        assert!(find("brokenness", Kind::Err).is_empty());
    }

    #[test]
    fn assignments_are_keys_but_labels_stay_keywords() {
        let mut cfg = ScanCfg::default();
        cfg.numbers = true;
        let row = hits("errors=0 failed=yes", &cfg);
        assert_eq!(row[0], (0, 6, Kind::Key));
        assert_eq!(row[1], (7, 8, Kind::Num));
        // `ERROR:` is a severity label, not a key.
        let row = hits("ERROR: boom", &cfg);
        assert_eq!(row[0], (0, 5, Kind::Err));
    }

    #[test]
    fn hashes() {
        assert_eq!(find("commit 3f2a1c9dd0", Kind::Hash), ["3f2a1c9dd0"]);
        assert!(find("word 1234", Kind::Hash).is_empty());
    }

    #[test]
    fn quoted_strings() {
        assert_eq!(find("msg \"hello world\" end", Kind::Str), ["hello world"]);
    }

    #[test]
    fn ansi_sequences_are_skipped() {
        // The escape payload must not be classified as a number or a key.
        let cfg = ScanCfg::default();
        let row = hits("\x1b[1;32mOK\x1b[0m", &cfg);
        assert!(row.iter().all(|(s, _, _)| *s >= 7));
    }

    #[test]
    fn header_heuristic() {
        let mut cfg = ScanCfg::default();
        cfg.headers = true;
        let row = hits("Filesystem      Size  Used Avail Use% Mounted on", &cfg);
        assert_eq!(row.len(), 1);
        assert_eq!(row[0].2, Kind::Hdr);
        let row = hits("[    0.000000] Linux version 6.12", &cfg);
        assert!(row.iter().all(|(_, _, k)| *k != Kind::Hdr));
    }

    #[test]
    fn structure_markers() {
        let mut cfg = ScanCfg::default();
        cfg.numbers = false;
        let row = hits("a -> b | c::d", &cfg);
        assert_eq!(row.len(), 3);
        assert!(row.iter().all(|(_, _, k)| *k == Kind::Sep));
    }
}
