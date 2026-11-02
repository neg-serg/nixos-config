//! `dsh-patch` - the exact-string, count-asserted patcher for dsh.
//!
//! The build-time patch sets (formerly `packages/dsh/patch-*.py`) run against
//! the unpacked npm tree, and the profile caretaker subcommands (formerly
//! `modules/user/nix-maid/apps/dsh-*.py`) rewrite the terminal profile's
//! `cordis.patch.yml`, the liangshen preset and `~/.dsh/settings.yaml`.
//!
//! Exit codes follow the scripts they replace: 0 success, 1 a failed
//! assertion or I/O error, 2 a usage error.

mod engine;
mod liangshen;
mod models_settings;
mod patches;
mod tui_preset;

const USAGE: &str = "\
usage: dsh-patch <command> ...

commands:
  widgets <node_modules/@deepseek-ai>   dsh-widgets bundle patches
  session-format <dir>                  released-0.1.x session payloads
  session-migration <dir>               interrupted-turn repair for v3 logs
  ptc-env <dir>                         keep LD_LIBRARY_PATH in PTC workers
  models-settings <settings.yaml> <blocks.json>
  tui-preset <patch.yml> <rows> <presets.json> [prefix]
  liangshen-prune <agent.cordis.yml>";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(dispatch(&args));
}

fn dispatch(args: &[String]) -> i32 {
    let Some(command) = args.first().map(String::as_str) else {
        eprintln!("{USAGE}");
        return 2;
    };
    let rest = &args[1..];
    match command {
        "widgets" => run_set(
            rest,
            "patch-widgets",
            patches::WIDGETS,
            Some(patches::WIDGETS_DONE),
        ),
        "session-format" => run_set(
            rest,
            "patch-session-format",
            patches::SESSION_FORMAT,
            Some(patches::SESSION_FORMAT_DONE),
        ),
        "session-migration" => run_set(
            rest,
            "patch-session-migration",
            patches::SESSION_MIGRATION,
            Some(patches::SESSION_MIGRATION_DONE),
        ),
        "ptc-env" => run_set(rest, "patch-ptc-env", patches::PTC_ENV, None),
        "models-settings" => models_settings::run(rest),
        "tui-preset" => tui_preset::run(rest),
        "liangshen-prune" => liangshen::run(rest),
        other => {
            eprintln!("dsh-patch: unknown command: {other}");
            eprintln!("{USAGE}");
            2
        }
    }
}

fn run_set(
    rest: &[String],
    prog: &str,
    files: &'static [engine::FilePatch],
    done: Option<&str>,
) -> i32 {
    let Some(root) = rest.first() else {
        eprintln!("{USAGE}");
        return 2;
    };
    let code = engine::run_patch_set(root, prog, files);
    if code == 0 {
        if let Some(message) = done {
            println!("{message}");
        }
    }
    code
}
