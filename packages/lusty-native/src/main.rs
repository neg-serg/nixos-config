//! lusty-native: native file/buffer picker for Neovim.
//!
//! Phase 1-3: --list mode (benchmark + plumbing) with depth/skip/mount
//! semantics, query ranking and LS_COLORS-aware coloring. The TUI lands in a
//! later phase.

mod colors;
mod fuzzy;
mod glob;
mod listing;
mod mount;
mod rank;
mod serve;
mod tui;

use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::time::Instant;

use listing::FileKind;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(|s| s.as_str()) == Some("--list") {
        run_list(&args);
        return;
    }
    if args.first().map(|s| s.as_str()) == Some("serve") {
        let mut root = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let mut depth = 2usize;
        let mut skip = "pic,tmp".to_string();
        let mut show_dots = false;
        let mut i = 1;
        while i < args.len() {
            match args[i].as_str() {
                "--depth" => {
                    i += 1;
                    depth = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(2);
                }
                "--skip" => {
                    i += 1;
                    skip = args.get(i).cloned().unwrap_or_default();
                }
                "--dots" => show_dots = true,
                other if !other.starts_with("--") => {
                    root = PathBuf::from(other);
                }
                _ => {}
            }
            i += 1;
        }
        let _ = serve::serve(
            root,
            depth,
            skip.split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            show_dots,
        );
        return;
    }
    // Interactive picker: lusty-native [root] [--depth N] [--skip a,b]
    let mut root = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let mut depth = 2usize;
    let mut skip = "pic,tmp".to_string();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--depth" => {
                i += 1;
                depth = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(2);
            }
            "--skip" => {
                i += 1;
                skip = args.get(i).cloned().unwrap_or_default();
            }
            other if !other.starts_with("--") => {
                root = PathBuf::from(other);
            }
            _ => {}
        }
        i += 1;
    }
    let opts = listing::Options {
        depth,
        skip_dirs: skip
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        follow_mounts: false,
        show_dots: false,
    };
    let mut app = tui::App::new(root, opts);
    match app.run() {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("lusty-native: {err}");
            std::process::exit(2);
        }
    }
}

fn run_list(args: &[String]) {
    let mut root: Option<PathBuf> = None;
    let mut depth = 2usize;
    let mut show_dots = false;
    let mut color = false;
    let mut skip = "pic,tmp".to_string();
    let mut query = String::new();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--depth" => {
                i += 1;
                depth = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(2);
            }
            "--show-dots" => show_dots = true,
            "--color" => color = true,
            "--query" => {
                i += 1;
                query = args.get(i).cloned().unwrap_or_default();
            }
            "--skip" => {
                i += 1;
                skip = args.get(i).cloned().unwrap_or_default();
            }
            other if !other.starts_with("--") && root.is_none() => {
                root = Some(PathBuf::from(other));
            }
            _ => {}
        }
        i += 1;
    }

    let root = root.unwrap_or_else(|| PathBuf::from("."));
    let opts = listing::Options {
        depth,
        skip_dirs: skip
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        follow_mounts: false,
        show_dots,
    };

    let t0 = Instant::now();
    let entries = listing::list(&root, &opts);
    let dt_list = t0.elapsed();
    let total = entries.len();

    let idxs: Vec<usize> = if query.is_empty() {
        eprintln!("{} entries in {:?}", total, dt_list);
        (0..total).collect()
    } else {
        let t1 = Instant::now();
        let idxs = rank::rank_indices(&entries, &query);
        eprintln!(
            "{} of {} entries in {:?} (list) + {:?} (rank)",
            idxs.len(),
            total,
            dt_list,
            t1.elapsed()
        );
        idxs
    };

    let palette = if color { Some(colors::load()) } else { None };
    let esc = char::from_u32(0x1b).unwrap();

    let mut out = String::new();
    for &i in &idxs {
        let e = &entries[i];
        let code = palette.as_ref().and_then(|p| {
            let exec = e.kind == FileKind::File && is_exec(&e.path);
            p.code_for(&e.name, e.kind, exec)
        });
        push_label(&mut out, e, code, esc);
    }
    print!("{out}");
}

fn is_exec(path: &std::path::Path) -> bool {
    std::fs::metadata(path)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn push_label(out: &mut String, e: &listing::Entry, code: Option<&str>, esc: char) {
    if let Some(code) = code {
        out.push(esc);
        out.push('[');
        out.push_str(code);
        out.push('m');
    }
    out.push_str(&e.label);
    if e.kind == FileKind::Dir {
        out.push('/');
    }
    if code.is_some() {
        out.push(esc);
        out.push_str("[0m");
    }
    out.push('\n');
}
