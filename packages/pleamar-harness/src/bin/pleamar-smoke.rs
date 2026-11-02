//! `pleamar-smoke`: the port of `files/pleamar/scripts/smoke.sh`.

use std::env;
use std::process::exit;

use pleamar_harness::ctx::Ctx;
use pleamar_harness::repo;
use pleamar_harness::smoke::{self, Parsed};

fn main() {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let options = match smoke::parse_args(&args) {
        Ok(Parsed::Help) => {
            smoke::say_usage();
            exit(0);
        }
        Ok(Parsed::Run(options)) => options,
        Err(halt) => {
            halt.report("smoke");
            exit(halt.code());
        }
    };
    let project = match repo::project_root() {
        Ok(project) => project,
        Err(error) => {
            eprintln!("smoke: error: {error}");
            exit(2);
        }
    };
    let mut ctx = Ctx::new("smoke", project);
    let code = match smoke::run(&mut ctx, options) {
        Ok(code) => code,
        Err(halt) => {
            halt.report("smoke");
            halt.code()
        }
    };
    ctx.cleanup();
    exit(code);
}
