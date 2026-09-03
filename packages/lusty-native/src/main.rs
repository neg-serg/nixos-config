//! lusty-native: native file/buffer picker for Neovim.
//!
//! Phase 1 exposes a --list mode for benchmarking the listing engine against
//! the Lua port (readdir + getftype per entry). The TUI lands in a later phase.

mod glob;
mod listing;
mod mount;

use std::path::PathBuf;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(|s| s.as_str()) == Some("--list") {
        run_list(&args);
        return;
    }
    eprintln!("usage: lusty-native --list <root> [--depth N] [--show-dots] [--skip a,b]");
    std::process::exit(2);
}

fn run_list(args: &[String]) {
    let mut root: Option<PathBuf> = None;
    let mut depth = 2usize;
    let mut show_dots = false;
    let mut skip = "pic,tmp".to_string();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--depth" => {
                i += 1;
                depth = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(2);
            }
            "--show-dots" => show_dots = true,
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
    let dt = t0.elapsed();

    let mut out = String::new();
    for e in &entries {
        out.push_str(&e.name);
        if e.is_dir {
            out.push('/');
        }
        out.push('\n');
    }
    print!("{out}");
    eprintln!("{} entries in {:?}", entries.len(), dt);
}
