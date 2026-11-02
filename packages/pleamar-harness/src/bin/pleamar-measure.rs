//! `pleamar-measure`: the port of `files/pleamar/scripts/measure.sh`.

use std::env;
use std::process::exit;

use pleamar_harness::ctx::Ctx;
use pleamar_harness::measure::{self, Parsed};
use pleamar_harness::repo;

fn main() {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let options = match measure::parse_args(&args) {
        Ok(Parsed::Help) => {
            measure::say_usage();
            exit(0);
        }
        Ok(Parsed::Run(options)) => options,
        Err(halt) => {
            halt.report("measure");
            exit(halt.code());
        }
    };
    let project = match repo::project_root() {
        Ok(project) => project,
        Err(error) => {
            eprintln!("measure: error: {error}");
            exit(2);
        }
    };
    let mut ctx = Ctx::new("measure", project);
    let code = match measure::run(&mut ctx, options) {
        Ok(code) => code,
        Err(halt) => {
            halt.report("measure");
            halt.code()
        }
    };
    ctx.cleanup();
    exit(code);
}
