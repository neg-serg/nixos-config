//! `pleamar-rig`: a copy of the shell in a headless `pleamar-wm`, to look at and
//! poke without touching the desktop in use.

use std::env;
use std::process::exit;

use pleamar_harness::ctx::Ctx;
use pleamar_harness::repo;
use pleamar_harness::rig::{self, Parsed};

fn main() {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let options = match rig::parse_args(&args) {
        Ok(Parsed::Help) => {
            print!("{}", rig::USAGE);
            exit(0);
        }
        Ok(Parsed::Run(options)) => options,
        Err(halt) => {
            halt.report("rig");
            exit(halt.code());
        }
    };
    let project = match repo::project_root() {
        Ok(project) => project,
        Err(error) => {
            eprintln!("rig: error: {error}");
            exit(2);
        }
    };
    let mut ctx = Ctx::new("rig", project);
    let code = match rig::run(&mut ctx, options) {
        Ok(code) => code,
        Err(halt) => {
            halt.report("rig");
            halt.code()
        }
    };
    ctx.cleanup();
    exit(code);
}
