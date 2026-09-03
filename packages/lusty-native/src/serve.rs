//! Headless backend for the nvim shim.
//!
//! Runs one listing in memory and answers plain-text requests on stdin, one
//! per line, so the nvim side can render results in a normal floating window
//! (no terminal buffer involved):
//!
//!   E                     -> "C <total> <depth> <root>"  (ready)
//!   Q <from> <to> <query>  -> "N <matched>", then "R <i> <kind> <label>"
//!                            rows for indices in [from,to) of the ranking
//!   P <ranked-index>       -> "P <absolute path>"
//!
//! kind is one of d/f/l (dir/file/link). Lines are '\n'-terminated; labels
//! are raw (no ANSI). The process exits on stdin EOF.

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use crate::listing::{self, FileKind, Options};
use crate::rank;

pub fn serve(root: PathBuf, depth: usize, skip_dirs: Vec<String>, show_dots: bool) -> io::Result<()> {
    let opts = Options {
        depth,
        skip_dirs,
        follow_mounts: false,
        show_dots,
    };
    let entries = listing::list(&root, &opts);
    let mut ranked: Vec<usize> = (0..entries.len()).collect();

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    if let Ok(db) = std::env::var("LUSTY_SERVE_DEBUG") {
        let _ = std::fs::write(&db, format!("entries={} C-about-to-print", entries.len()));
    }
    writeln!(
        out,
        "C {} {} {}",
        entries.len(),
        depth,
        root.display()
    )?;
    out.flush()?;
    if let Ok(db) = std::env::var("LUSTY_SERVE_DEBUG") {
        let mut f = std::fs::OpenOptions::new().append(true).open(&db).unwrap();
        use std::io::Write as _;
        let _ = f.write_all(b" C-printed\n");
    }

    let mut current_query = String::new();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let parts: Vec<&str> = line.splitn(4, '\t').collect();
        match parts[0] {
            "Q" => {
                let from: usize = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
                let to: usize = parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(0);
                current_query = parts.get(3).unwrap_or(&"").to_string();
                ranked = if current_query.is_empty() {
                    (0..entries.len()).collect()
                } else {
                    rank::rank_indices(&entries, &current_query)
                };
                writeln!(out, "N {}", ranked.len())?;
                // max label char count of the ranked set (column sizing)
                let maxw = ranked
                    .iter()
                    .map(|&i| entries[i].label.chars().count())
                    .max()
                    .unwrap_or(0);
                writeln!(out, "W {}", maxw)?;
                let end = to.min(ranked.len());
                for &i in &ranked[from.min(ranked.len())..end] {
                    let e = &entries[i];
                    let kind = match e.kind {
                        FileKind::Dir => 'd',
                        FileKind::Link => 'l',
                        _ => 'f',
                    };
                    writeln!(out, "R {} {} {}\t{}", i, kind, e.label, e.path.display())?;
                }
                writeln!(out, "E")?;
                out.flush()?;
            }
            "D" => {
                // top-level directories (depth 1) for '/' completion
                for e in &entries {
                    if e.depth == 1 && e.kind == FileKind::Dir {
                        writeln!(out, "D {}", e.name)?;
                    }
                }
                writeln!(out, "E")?;
                out.flush()?;
            }
            "P" => {
                let i: usize = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
                if i < entries.len() {
                    writeln!(out, "P {}", entries[i].path.display())?;
                } else {
                    writeln!(out, "P ")?;
                }
                writeln!(out, "E")?;
                out.flush()?;
            }
            _ => {}
        }
    }
    Ok(())
}
