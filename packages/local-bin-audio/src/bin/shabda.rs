//! Rust port of `packages/local-bin/bin/shabda`.
//!
//! Opens the Shabda Freesound-pack browser and/or builds the Tidal `!reslist`
//! or Strudel `samples(...)` line for a pack. `getopts "sla"` is reimplemented
//! with bash's exact observable behaviour (illegal option diagnostics, combined
//! options, `--`), `dirname`/string building are native, and the tools that
//! actually do something stay subprocesses with the original argv: `vivaldi`,
//! `mkdir`, `grep` and `wl-copy`.

use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Input, Sink};
use local_bin_audio::text;

const BASE: &[u8] = b"https://shabda.ndre.gr";
const LICENSES: &[u8] = b"by,cc0,by-nc";

struct Options {
    strudel: bool,
    list_only: bool,
    append: bool,
    operands: Vec<Vec<u8>>,
}

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let raw: Vec<Vec<u8>> = arguments
        .map(|value| env::os_bytes(&value).to_vec())
        .collect();

    let options = match parse_options(&program, &raw) {
        Some(options) => options,
        None => std::process::exit(2),
    };
    let pack = options.operands.first().cloned().unwrap_or_default();

    // No pack: open the site and explain the next step.
    if pack.is_empty() {
        open_browser(&program, 40);
        env::out_str("Shabda opened in the browser: https://shabda.ndre.gr\n");
        env::out_str("Pick a pack there, then run:  shabda <pack>\n");
        return;
    }

    let line = if options.strudel {
        let mut line = b"samples('".to_vec();
        line.extend_from_slice(BASE);
        line.push(b'/');
        line.extend_from_slice(&pack);
        line.extend_from_slice(b".json?strudel=1&licenses=");
        line.extend_from_slice(LICENSES);
        line.extend_from_slice(b"')");
        line
    } else {
        let mut line = b"!reslist \"".to_vec();
        line.extend_from_slice(BASE);
        line.push(b'/');
        line.extend_from_slice(&pack);
        line.extend_from_slice(b".json?licenses=");
        line.extend_from_slice(LICENSES);
        line.push(b'"');
        line
    };

    let home = env::var_or_empty("HOME");

    if options.append {
        let out = {
            let mut path = home.clone();
            path.extend_from_slice(b"/notes/music/tidal/shabda-samples.json");
            path
        };
        let directory = text::dirname(&out);
        let mkdir = Cmd::new("mkdir")
            .arg("-p")
            .arg_bytes(&directory)
            .diag(&program, 59)
            .run();
        if mkdir.code != 0 {
            std::process::exit(mkdir.code);
        }

        let mut already = false;
        if Path::new(OsStr::from_bytes(&out)).is_file() {
            let mut pattern = pack.clone();
            pattern.extend_from_slice(b".json");
            let found = Cmd::new("grep")
                .arg("-q")
                .arg_bytes(&pattern)
                .arg_bytes(&out)
                .stderr(Sink::Null)
                .diag(&program, 60)
                .run();
            already = found.code == 0;
        }

        if already {
            let mut message = b"already in ".to_vec();
            message.extend_from_slice(&out);
            message.push(b'\n');
            env::out(&message);
            return;
        }

        let mut entry = line.clone();
        entry.push(b'\n');
        let append = fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(Path::new(OsStr::from_bytes(&out)));
        match append {
            Ok(mut file) => {
                if file.write_all(&entry).is_err() {
                    std::process::exit(1);
                }
            }
            Err(error) => {
                env::err(&env::redirect_failure_message(&program, 63, &out, &error));
                std::process::exit(1);
            }
        }
        let mut message = b"appended to ".to_vec();
        message.extend_from_slice(&out);
        message.push(b'\n');
        env::out(&message);
        return;
    }

    if options.list_only {
        env::out_line(&line);
        return;
    }

    if env::which(b"wl-copy") {
        let copy = Cmd::new("wl-copy")
            .stdin(Input::Bytes(&line))
            .diag(&program, 76)
            .run();
        if copy.code != 0 {
            std::process::exit(copy.code);
        }
        let mut message = b"copied: ".to_vec();
        message.extend_from_slice(&line);
        message.push(b'\n');
        env::out(&message);
    } else {
        env::out_line(&line);
    }

    open_browser(&program, 81);
    env::out_str("Shabda opened (paste the copied line into Tidal/Strudel).\n");
}

/// bash `getopts "sla"`: options are consumed until the first operand, `--` or
/// a lone `-`; an unknown option prints the diagnostic and ends the port with
/// the script's usage line (`exit 2`).
fn parse_options(program: &[u8], arguments: &[Vec<u8>]) -> Option<Options> {
    let mut options = Options {
        strudel: false,
        list_only: false,
        append: false,
        operands: Vec::new(),
    };
    let mut index = 0;
    let mut position = 1;
    while index < arguments.len() {
        let argument = &arguments[index];
        if position == 1 {
            if argument.len() < 2 || argument[0] != b'-' {
                break;
            }
            if argument == b"--" {
                index += 1;
                break;
            }
        }
        let option = argument[position];
        match option {
            b's' => options.strudel = true,
            b'l' => options.list_only = true,
            b'a' => options.append = true,
            other => {
                let mut message = program.to_vec();
                message.extend_from_slice(b": illegal option -- ");
                message.push(other);
                message.push(b'\n');
                env::err(&message);
                let mut usage = b"usage: ".to_vec();
                usage.extend_from_slice(program);
                usage.extend_from_slice(b" [-s|-l|-a] [pack]\n");
                env::err(&usage);
                return None;
            }
        }
        position += 1;
        if position >= argument.len() {
            index += 1;
            position = 1;
        }
    }
    options.operands = arguments[index..].to_vec();
    Some(options)
}

fn open_browser(program: &[u8], line: u32) {
    let _ = Cmd::new("vivaldi")
        .arg_bytes(BASE)
        .stdin(Input::Null)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, line)
        .spawn_async();
}
