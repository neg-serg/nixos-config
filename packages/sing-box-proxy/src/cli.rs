//! CLI dispatch: `proxy [on|off|status|refresh|gen|run <cmd...>]`.
//!
//! No arguments means `status` (like the shell's `CMD="status"` default).
//! `on`/`start`, `off`/`stop`, `gen`/`bootstrap`, `run`/`exec` keep the shell's
//! aliases; anything else is an unknown command (exit 1, usage line on stderr).

use crate::output::Ui;
use crate::paths::Paths;
use crate::{refresh, service};
use std::io;

pub fn run(args: &[String]) -> i32 {
    let argv0 = args.first().map(String::as_str).unwrap_or("proxy");
    let command = args.get(1).map(String::as_str).unwrap_or("status");
    let paths = Paths::from_env();

    let mut stderr = io::stderr();
    let mut ui = Ui::stderr(&mut stderr);

    match command {
        "on" | "start" => {
            // `bootstrap; start` under `set -e`: stop when bootstrap failed.
            let rc = service::bootstrap(&mut ui, &paths);
            if rc != 0 {
                return rc;
            }
            service::start(&mut ui, &paths)
        }
        "off" | "stop" => service::stop(&mut ui, &paths),
        "refresh" => refresh::run(&mut ui, &paths),
        "gen" | "bootstrap" => service::bootstrap(&mut ui, &paths),
        "run" | "exec" => service::run_command(&mut ui, argv0, &args[2..]),
        "status" => {
            let stdout = io::stdout();
            let mut out = stdout.lock();
            service::status(&mut ui, &mut out, &paths)
        }
        other => {
            ui.fail(&format!("unknown command: {other}"));
            eprintln!("Usage: {argv0} {{on|off|status|refresh|gen|run <cmd...>}}");
            1
        }
    }
}
