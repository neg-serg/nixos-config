//! `pleamar-describe-snap`: the port of
//! `files/pleamar/scripts/describe-snap.sh`.

use std::env;
use std::process::exit;

use pleamar_harness::ctx::Ctx;
use pleamar_harness::describe::{self, Parsed};
use pleamar_harness::repo;

fn main() {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let options = match describe::parse_args(&args) {
        Ok(Parsed::Help) => {
            describe::say_usage();
            exit(0);
        }
        Ok(Parsed::Run(options)) => options,
        Err(halt) => {
            halt.report("describe-snap");
            exit(halt.code());
        }
    };
    let project = match repo::project_root() {
        Ok(project) => project,
        Err(error) => {
            eprintln!("describe-snap: error: {error}");
            exit(2);
        }
    };
    let mut ctx = Ctx::new("describe-snap", project);
    let code = match describe::run(&mut ctx, options) {
        Ok(code) => code,
        Err(halt) => {
            halt.report("describe-snap");
            halt.code()
        }
    };
    ctx.cleanup();
    exit(code);
}
