//! `music-index`: build the MERT similarity index for a music library.
//!
//! The ML embedding runs in the existing `music-embed` executable; this binary
//! owns the scan, cache, migration, audit and index-file logic.

use std::io::{self, Write};
use std::path::PathBuf;

use music_index_tools::fsutil;
use music_index_tools::index::{self, BuildOptions, Settings};

fn main() {
    std::process::exit(run());
}

fn run() -> i32 {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match index::parse_args(&argv) {
        Ok(args) => args,
        Err(error) => {
            let _ = writeln!(io::stderr(), "{}", index::usage());
            let _ = writeln!(io::stderr(), "music-index: error: {error}");
            return 2;
        }
    };
    if args.help {
        let _ = write!(io::stdout(), "{}", index::help());
        return 0;
    }
    if args.selftest {
        return index::selftest();
    }

    let root = fsutil::expand_user(&PathBuf::from(&args.root));
    let out_dir = fsutil::expand_user(&PathBuf::from(&args.out));
    if args.audit {
        return index::audit_index(
            &root,
            &out_dir,
            args.audit_limit,
            &mut io::stdout(),
            &mut io::stderr(),
        );
    }

    let settings = Settings {
        model: args.model.clone(),
        layer: index::resolve_layer(&args.model, args.layer),
        window_seconds: args.window_seconds,
        windows: args.windows,
    };
    let options = BuildOptions {
        settings,
        device: args.device,
        jobs: args.jobs,
        limit: args.limit,
        rebuild: args.rebuild,
        quiet: args.quiet,
        threads: args.threads,
        adopt_legacy: args.adopt_legacy,
    };
    index::build_index(&root, &out_dir, &options, None, &mut io::stderr())
}
