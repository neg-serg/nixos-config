//! `music-similar`: nearest neighbours of a track from a music-index directory.
//!
//! Without an AUDIO argument the current MPRIS track is used, which makes the
//! binary a one-liner for a compositor key binding.

use std::io::{self, Write};

use music_index_tools::similar;

fn main() {
    std::process::exit(run());
}

fn run() -> i32 {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match similar::parse_args(&argv) {
        Ok(args) => args,
        Err(error) => {
            let _ = writeln!(io::stderr(), "{}", similar::usage());
            let _ = writeln!(io::stderr(), "music-similar: error: {error}");
            return 2;
        }
    };
    if args.help {
        let _ = write!(io::stdout(), "{}", similar::help());
        return 0;
    }
    if args.selftest {
        return similar::selftest();
    }
    similar::run(&args, &mut io::stdout(), &mut io::stderr())
}
