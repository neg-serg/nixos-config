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

/// True when the digit run continues an identifier: `i2c-11`, `nvme0`, `a_5`.
/// A number after a space, a colon or an opening bracket is a value.
fn inside_identifier(line: &[u8], i: usize) -> bool {
    if i == 0 {
        return false;
    }
    match line[i - 1] {
        b if is_word_byte(b) => true,
        b'-' => i >= 2 && is_word_byte(line[i - 2]),
        _ => false,
    }
}

/// Byte-class tables: a match with ten alternatives per byte is the hot spot in
/// the scanners, a table lookup is a single load.
const fn class_table() -> [bool; 256] {
    let mut table = [false; 256];
    let mut i = 0;
    while i < 256 {
        let b = i as u8;
        table[i] = b.is_ascii_alphanumeric() || b == b'_';
        i += 1;
    }
    table
}

const fn relpath_table() -> [bool; 256] {
    let mut table = [false; 256];
    let mut i = 0;
    while i < 256 {
        let b = i as u8;
        table[i] = b.is_ascii_alphanumeric()
            || matches!(b, b'/' | b'.' | b'_' | b'-' | b'+' | b'@' | b'%');
        i += 1;
    }
    table
}

static WORD_BYTE: [bool; 256] = class_table();
static RELPATH_BYTE: [bool; 256] = relpath_table();

fn is_word_byte(b: u8) -> bool {
    WORD_BYTE[b as usize]
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
    if cfg.hashes {
        if let Some(end) = try_uuid(line, i) {
            out.push(Hit::new(i, end, Kind::Hash, PRIO_NUM));
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
    if cfg.numbers && !inside_identifier(line, i) {
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

/// `123e4567-e89b-12d3-a456-426614174000`: eight, four, four, four, twelve.
fn try_uuid(line: &[u8], i: usize) -> Option<usize> {
    const GROUPS: [usize; 5] = [8, 4, 4, 4, 12];
    // Two cheap rejects before the group walk: most tokens are not UUIDs.
    if i + 36 > line.len() || line[i + 8] != b'-' || line[i + 13] != b'-' {
        return None;
    }
    if !boundary_before(line, i) {
        return None;
    }
    let mut j = i;
    for (index, len) in GROUPS.iter().enumerate() {
        if j + len > line.len() || !line[j..j + len].iter().all(|b| is_hex(*b)) {
            return None;
        }
        j += len;
        if index < GROUPS.len() - 1 {
            if line.get(j) != Some(&b'-') {
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
    // Require a digit *and* a letter: `frontend` is not an object id, and a
    // seven-digit PID (`2255555`) is a number, not a hash.
    let slice = &line[i..j];
    if !slice.iter().any(u8::is_ascii_digit) || !slice.iter().any(u8::is_ascii_alphabetic) {
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
    let end = match line.get(j) {
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
    // Relative paths (`src/main.rs`, `target/debug/tint`) carry a slash and at
    // least one letter; absolute ones are handled on the `/` path.
    if cfg.paths && boundary_before(line, i) {
        if let Some(end) = try_relpath(line, i) {
            out.push(Hit::new(i, end, Kind::Path, PRIO_PATH));
            return Some(end);
        }
    }
    // IPv6 and MAC addresses may start with a hex letter (`fe80::1`, `aa:bb:..`),
    // so they are tried here as well as on the numeric path.
    if cfg.hashes && boundary_before(line, i) {
        if let Some(end) = try_uuid(line, i) {
            out.push(Hit::new(i, end, Kind::Hash, PRIO_NUM));
            return Some(end);
        }
    }
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
                let inner = &line[i + 1..j];
                // `'/nix/store/x.drv'` is a path in quotes: let the path scanner
                // colour it instead of painting the whole string green.
                let bare_path = !inner.is_empty()
                    && (inner[0] == b'/' || inner[0] == b'~' || inner.starts_with(b"./"))
                    && !inner.iter().any(|b| b.is_ascii_whitespace());
                if bare_path {
                    return Some(i + 1);
                }
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

/// A token that looks like a relative path: `src/main.rs`, `a/b/c`, `./x`.
fn try_relpath(line: &[u8], i: usize) -> Option<usize> {
    let n = line.len();
    let mut j = i;
    let mut slashes = 0;
    let mut letters = 0;
    while j < n && RELPATH_BYTE[line[j] as usize] {
        let b = line[j];
        if b == b'/' {
            slashes += 1;
        } else if b.is_ascii_alphabetic() {
            letters += 1;
        }
        j += 1;
    }
    if slashes == 0 || letters == 0 || j - i < 3 {
        return None;
    }
    // Trailing punctuation belongs to the sentence, not the path; `a//b` is not
    // a path either.
    while j > i && matches!(line[j - 1], b'.' | b'-' | b'/' | b'%' | b'@') {
        j -= 1;
    }
    let slice = &line[i..j];
    if slice.windows(2).any(|w| w == b"//") || slice.is_empty() {
        return None;
    }
    // One slash alone is too weak a signal (`and/or`, `read/write`, the `df`
    // pool name `tank/nixos`): ask for a second slash or an extension.
    let last_segment = &slice[slice.iter().rposition(|b| *b == b'/').unwrap_or(0) + 1..];
    let has_extension = last_segment.iter().any(|b| *b == b'.') && last_segment.len() > 1;
    let solid = slice.iter().filter(|b| **b == b'/').count() >= 2 || has_extension;
    if !solid {
        return None;
    }
    if !boundary_after(line, j) {
        return None;
    }
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

/// Word → severity, sorted for binary search.
static KEYWORDS: &[(&str, Kind)] = &[
    ("abort", Kind::Err),
    ("aborted", Kind::Err),
    ("active", Kind::Ok),
    ("alive", Kind::Ok),
    ("already", Kind::Note),
    ("available", Kind::Ok),
    ("broken", Kind::Err),
    ("building", Kind::Info),
    ("built", Kind::Info),
    ("cached", Kind::Note),
    ("cannot", Kind::Err),
    ("changed", Kind::Note),
    ("connected", Kind::Ok),
    ("copying", Kind::Info),
    ("corrupt", Kind::Err),
    ("corrupted", Kind::Err),
    ("crash", Kind::Err),
    ("crashed", Kind::Err),
    ("created", Kind::Info),
    ("creating", Kind::Info),
    ("critical", Kind::Err),
    ("dead", Kind::Warn),
    ("debug", Kind::Dim),
    ("degraded", Kind::Warn),
    ("denied", Kind::Err),
    ("deprecated", Kind::Warn),
    ("died", Kind::Err),
    ("dirty", Kind::Warn),
    ("disabled", Kind::Warn),
    ("done", Kind::Ok),
    ("down", Kind::Warn),
    ("enabled", Kind::Ok),
    ("err", Kind::Err),
    ("error", Kind::Err),
    ("errors", Kind::Err),
    ("established", Kind::Ok),
    ("exceeded", Kind::Err),
    ("expired", Kind::Warn),
    ("fail", Kind::Err),
    ("failed", Kind::Err),
    ("failure", Kind::Err),
    ("false", Kind::Warn),
    ("fatal", Kind::Err),
    ("flaky", Kind::Warn),
    ("found", Kind::Ok),
    ("healthy", Kind::Ok),
    ("hint", Kind::Note),
    ("inactive", Kind::Warn),
    ("info", Kind::Info),
    ("information", Kind::Info),
    ("invalid", Kind::Err),
    ("killed", Kind::Err),
    ("listening", Kind::Ok),
    ("loaded", Kind::Ok),
    ("loading", Kind::Info),
    ("missing", Kind::Err),
    ("modified", Kind::Note),
    ("mounted", Kind::Ok),
    ("mounting", Kind::Info),
    ("nan", Kind::Dim),
    ("nil", Kind::Dim),
    ("no", Kind::Warn),
    ("none", Kind::Dim),
    ("note", Kind::Note),
    ("notice", Kind::Info),
    ("null", Kind::Dim),
    ("off", Kind::Warn),
    ("ok", Kind::Ok),
    ("online", Kind::Ok),
    ("overflow", Kind::Err),
    ("panic", Kind::Err),
    ("pass", Kind::Ok),
    ("passed", Kind::Ok),
    ("phase", Kind::Info),
    ("reached", Kind::Note),
    ("ready", Kind::Ok),
    ("refused", Kind::Err),
    ("retries", Kind::Warn),
    ("retry", Kind::Warn),
    ("retrying", Kind::Warn),
    ("running", Kind::Ok),
    ("searched", Kind::Note),
    ("segfault", Kind::Err),
    ("skipped", Kind::Note),
    ("slow", Kind::Warn),
    ("stale", Kind::Warn),
    ("started", Kind::Info),
    ("starting", Kind::Info),
    ("stopped", Kind::Info),
    ("stopping", Kind::Info),
    ("succeeded", Kind::Ok),
    ("success", Kind::Ok),
    ("successful", Kind::Ok),
    ("suspicious", Kind::Warn),
    ("timed", Kind::Err),
    ("timeout", Kind::Err),
    ("trace", Kind::Dim),
    ("true", Kind::Ok),
    ("unable", Kind::Err),
    ("unchanged", Kind::Note),
    ("undefined", Kind::Dim),
    ("unmodified", Kind::Note),
    ("unmounted", Kind::Warn),
    ("unreachable", Kind::Err),
    ("up", Kind::Ok),
    ("up-to-date", Kind::Note),
    ("verbose", Kind::Dim),
    ("warn", Kind::Warn),
    ("warning", Kind::Warn),
    ("warnings", Kind::Warn),
    ("yes", Kind::Ok),
];

/// Cheap 12-bit hash of a word: length, first byte and last byte.
///
/// Collisions are resolved by falling back to the sorted table, so the table
/// stays correct for any entry list; the point is that the common cases — a hit
/// and a clear miss — cost one load and at most one comparison, while a real
/// `HashMap` pays SipHash on every word of every line.
fn key_slot(word: &[u8]) -> usize {
    let len = word.len();
    ((len << 4) ^ (word[0] as usize) ^ ((word[len - 1] as usize) << 7)) & (SLOTS - 1)
}

const SLOTS: usize = 4096;
const SLOT_EMPTY: u16 = 0;
const SLOT_COLLIDED: u16 = u16::MAX;

/// keyword slot table: `index + 1` of the single candidate, `SLOT_COLLIDED`
/// when more than one keyword hashes there, `SLOT_EMPTY` when none does.
fn slot_table() -> &'static [u16; SLOTS] {
    static TABLE: std::sync::OnceLock<[u16; SLOTS]> = std::sync::OnceLock::new();
    TABLE.get_or_init(|| {
        let mut table = [SLOT_EMPTY; SLOTS];
        for (index, (word, _)) in KEYWORDS.iter().enumerate() {
            let bytes = word.as_bytes();
            let slot = key_slot(bytes);
            table[slot] = if table[slot] == SLOT_EMPTY {
                (index + 1) as u16
            } else {
                SLOT_COLLIDED
            };
        }
        table
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
    let lower = &buf[..word.len()];
    match slot_table()[key_slot(lower)] {
        SLOT_EMPTY => None,
        SLOT_COLLIDED => KEYWORDS
            .binary_search_by(|(candidate, _)| candidate.as_bytes().cmp(lower))
            .ok()
            .map(|index| KEYWORDS[index].1),
        slot => {
            let (candidate, kind) = KEYWORDS[slot as usize - 1];
            if candidate.as_bytes() == lower {
                Some(kind)
            } else {
                None
            }
        }
    }
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
        // A long all-digit field is a PID or a counter, not an object id.
        assert!(find("zsh 2255555 neg", Kind::Hash).is_empty());
    }

    #[test]
    fn digits_inside_identifiers_stay_plain() {
        let mut cfg = ScanCfg::default();
        cfg.numbers = true;
        let row = hits("spd5118-i2c-11-51 42 -7", &cfg);
        let numbers: Vec<&str> = row
            .iter()
            .filter(|(_, _, k)| *k == Kind::Num)
            .map(|(s, e, _)| &"spd5118-i2c-11-51 42 -7"[*s..*e])
            .collect();
        assert_eq!(numbers, ["42", "7"], "{row:?}");
    }

    #[test]
    fn relative_paths() {
        assert_eq!(find("built src/main.rs fine", Kind::Path), ["src/main.rs"]);
        assert_eq!(
            find("see target/debug/tint", Kind::Path),
            ["target/debug/tint"]
        );
        assert!(
            find("and/or ratio", Kind::Path).is_empty(),
            "words are not paths"
        );
        assert!(find("a//b", Kind::Path).is_empty());
    }

    #[test]
    fn quoted_strings() {
        assert_eq!(find("msg \"hello world\" end", Kind::Str), ["hello world"]);
        // A quoted path stays a path; a quoted sentence stays a string.
        assert_eq!(
            find("open '/nix/store/x.drv' now", Kind::Str),
            [] as [&str; 0]
        );
        assert_eq!(
            find("open '/nix/store/x.drv' now", Kind::Path),
            ["/nix/store/x.drv"]
        );
    }

    #[test]
    fn uuids_are_one_hash() {
        let uuid = "123e4567-e89b-12d3-a456-426614174000";
        assert_eq!(find(&format!("uuid {uuid} here"), Kind::Hash), [uuid]);
        assert_eq!(
            find(&format!("uuid {uuid} here"), Kind::Ip),
            [] as [&str; 0]
        );
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
