//! Serve-protocol integration test: the `serve` subcommand answers plain
//! line requests on stdin and emits row/metadata responses until EOF.
//!
//!   Q <from> <to> <query>       -> N/W/R rows + E (ranking, visible page)
//!   M <mask> <index>...         -> "K <i> <meta>" per entry index + E
//!
//! Cargo sets CARGO_BIN_EXE_lusty-native for integration tests, so the
//! real binary is exercised over pipes.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};

fn root_dir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("lusty_serve_m_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("subdir")).unwrap();
    std::fs::write(dir.join("alpha.txt"), b"hello").unwrap();
    dir
}

fn spawn(
    dir: &Path,
) -> (
    Child,
    ChildStdin,
    std::io::Lines<BufReader<std::process::ChildStdout>>,
) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_lusty-native"))
        .arg("serve")
        .arg(dir)
        .arg("--depth")
        .arg("1")
        .arg("--skip")
        .arg("")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn lusty-native serve");
    let stdin = child.stdin.take().expect("serve stdin");
    let stdout = child.stdout.take().expect("serve stdout");
    let lines = BufReader::new(stdout).lines();
    (child, stdin, lines)
}

/// Read response lines up to and including the "E" sentinel.
fn until_e(lines: &mut std::io::Lines<BufReader<std::process::ChildStdout>>) -> Vec<String> {
    let mut out = Vec::new();
    for line in lines {
        let line = line.expect("read serve line");
        if line == "E" {
            break;
        }
        out.push(line);
    }
    out
}

fn ask(stdin: &mut ChildStdin, req: &str) {
    writeln!(stdin, "{req}").unwrap();
    stdin.flush().unwrap();
}

/// Parse an R row: "R <i> <kind> <label>\t<path>".
fn row_parts(line: &str) -> (usize, char, &str) {
    let rest = &line[2..];
    let mut sp = rest.splitn(3, ' ');
    let i: usize = sp.next().unwrap().parse().unwrap();
    let kind = sp.next().unwrap().chars().next().unwrap();
    let label = sp.next().unwrap().split('\t').next().unwrap();
    (i, kind, label)
}

/// Parse a K row: "K <index> <meta>" (meta may be empty).
fn meta_parts(line: &str) -> (usize, String) {
    let rest = line.strip_prefix("K ").expect("K prefix");
    let (i, meta) = match rest.split_once(' ') {
        Some((i, m)) => (i.parse::<usize>().unwrap(), m.to_string()),
        None => (rest.parse::<usize>().unwrap(), String::new()),
    };
    (i, meta)
}

#[test]
fn serve_lists_all_on_empty_first_query() {
    // Regression: the ranking memo used to start at "" so the very first
    // Q (empty query, fresh picker) never ranked and returned N 0.
    let dir = root_dir();
    let (mut child, mut stdin, mut lines) = spawn(&dir);
    let c = lines.next().unwrap().unwrap();
    assert!(c.starts_with("C 2 1 "), "C line: {c}");

    ask(&mut stdin, "Q\t0\t50\t");
    let resp = until_e(&mut lines);
    assert_eq!(
        resp.first().map(String::as_str),
        Some("N 2"),
        "resp: {resp:?}"
    );
    assert!(resp.iter().any(|l| l.starts_with("W ")));
    let rows: Vec<(usize, char, &str)> = resp
        .iter()
        .filter(|l| l.starts_with("R "))
        .map(|l| row_parts(l))
        .collect();
    assert_eq!(rows.len(), 2);
    let labels: Vec<&str> = rows.iter().map(|r| r.2).collect();
    assert!(labels.contains(&"alpha.txt"));
    assert!(labels.contains(&"subdir"));

    drop(stdin);
    assert!(child.wait().unwrap().success());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn serve_m_returns_meta_per_index() {
    let dir = root_dir();
    let (mut child, mut stdin, mut lines) = spawn(&dir);
    let _ = lines.next().unwrap().unwrap(); // C line

    ask(&mut stdin, "Q\t0\t50\t");
    let resp = until_e(&mut lines);
    let rows: Vec<(usize, char, String)> = resp
        .iter()
        .filter(|l| l.starts_with("R "))
        .map(|l| {
            let (i, kind, label) = row_parts(l);
            (i, kind, label.to_string())
        })
        .collect();
    let alpha = rows
        .iter()
        .find(|r| r.2 == "alpha.txt")
        .expect("alpha row")
        .0;
    let subdir = rows.iter().find(|r| r.2 == "subdir").expect("subdir row").0;

    // Time renders as "YYYY-MM-DD HH:MM", so whitespace splits into five
    // tokens: perm user size date time.
    ask(&mut stdin, &format!("M\t15\t{alpha}\t{subdir}"));
    let meta_resp = until_e(&mut lines);
    assert_eq!(meta_resp.len(), 2, "resp: {meta_resp:?}");
    let (i_a, ma) = meta_parts(&meta_resp[0]);
    let (i_s, ms) = meta_parts(&meta_resp[1]);
    assert_eq!(i_a, alpha);
    assert_eq!(i_s, subdir);
    let fa: Vec<&str> = ma.split_whitespace().collect();
    assert_eq!(fa.len(), 5, "file meta: {ma}");
    assert_eq!(fa[0].len(), 10, "perms field");
    assert!(fa[0].starts_with('-'), "regular file perms: {}", fa[0]);
    let uid = std::fs::metadata(dir.join("alpha.txt")).unwrap().uid();
    assert_eq!(fa[1].trim(), uid.to_string(), "uid field");
    assert_eq!(fa[2], "5", "5-byte file human size");
    assert_eq!(fa[3].len(), 10, "YYYY-MM-DD field: {}", fa[3]);
    assert_eq!(fa[4].len(), 5, "HH:MM field: {}", fa[4]);
    assert!(fa[3].chars().nth(4) == Some('-'));
    assert!(fa[3].chars().nth(7) == Some('-'));
    assert!(fa[4].chars().nth(2) == Some(':'));
    let fd: Vec<&str> = ms.split_whitespace().collect();
    assert_eq!(fd.len(), 5, "dir meta: {ms}");
    assert!(fd[0].starts_with('d'), "dir perms: {}", fd[0]);

    // Single-field masks.
    ask(&mut stdin, &format!("M\t1\t{alpha}"));
    let r = until_e(&mut lines);
    let (_, m1) = meta_parts(&r[0]);
    assert_eq!(m1.split_whitespace().count(), 1);
    assert_eq!(m1.len(), 10);
    ask(&mut stdin, &format!("M\t4\t{alpha}"));
    let r = until_e(&mut lines);
    let (_, m4) = meta_parts(&r[0]);
    assert_eq!(m4.trim(), "5");
    ask(&mut stdin, &format!("M\t8\t{alpha}"));
    let r = until_e(&mut lines);
    let (_, m8) = meta_parts(&r[0]);
    assert_eq!(m8.len(), 16);

    // Mask 0 (no fields) still answers one K line per index, meta empty.
    ask(&mut stdin, &format!("M\t0\t{alpha}"));
    let r = until_e(&mut lines);
    assert_eq!(r.len(), 1);
    let (i0, m0) = meta_parts(&r[0]);
    assert_eq!(i0, alpha);
    assert_eq!(m0, "");

    // Out-of-range indices are skipped (empty response).
    ask(&mut stdin, "M\t15\t9999");
    let r = until_e(&mut lines);
    assert!(r.is_empty(), "resp: {r:?}");

    drop(stdin);
    assert!(child.wait().unwrap().success());
    let _ = std::fs::remove_dir_all(&dir);
}

/// Fixture whose canonical (depth, name) order deliberately differs from the
/// size and extension orders: a.txt (1 B), mm.md (5 B), z.txt (10 B).
fn sorted_dir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("lusty_serve_sort_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("a.txt"), b"x").unwrap();
    std::fs::write(dir.join("mm.md"), b"hello").unwrap();
    std::fs::write(dir.join("z.txt"), b"0123456789").unwrap();
    dir
}

fn ask_q(
    stdin: &mut ChildStdin,
    lines: &mut std::io::Lines<BufReader<std::process::ChildStdout>>,
    sort: u8,
) -> Vec<String> {
    ask(stdin, &format!("Q\t0\t50\t\t{sort}"));
    let resp = until_e(lines);
    assert_eq!(
        resp.first().map(String::as_str),
        Some("N 3"),
        "resp: {resp:?}"
    );
    resp.iter()
        .filter(|l| l.starts_with("R "))
        .map(|l| row_parts(l).2.to_string())
        .collect()
}

#[test]
fn serve_q_sort_cycles_and_resets() {
    // The Q request carries an optional sort token: 1 ext, 2 size desc,
    // 3 time desc; 0 restores the canonical depth+name order. Sorting must
    // always start from that canonical order (no stacking of sorts).
    let dir = sorted_dir();
    let (mut child, mut stdin, mut lines) = spawn(&dir);
    let _ = lines.next().unwrap().unwrap(); // C line

    let name = ask_q(&mut stdin, &mut lines, 0);
    assert_eq!(name, vec!["a.txt", "mm.md", "z.txt"]);

    let size = ask_q(&mut stdin, &mut lines, 2);
    assert_eq!(size, vec!["z.txt", "mm.md", "a.txt"]);

    let ext = ask_q(&mut stdin, &mut lines, 1);
    assert_eq!(ext, vec!["mm.md", "a.txt", "z.txt"]);

    let name_again = ask_q(&mut stdin, &mut lines, 0);
    assert_eq!(
        name_again,
        vec!["a.txt", "mm.md", "z.txt"],
        "reset to name order"
    );

    drop(stdin);
    assert!(child.wait().unwrap().success());
    let _ = std::fs::remove_dir_all(&dir);
}
