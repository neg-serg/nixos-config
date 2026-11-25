//! `argv[0]` dispatch shared by the multicall binaries.
//!
//! Every crate ships one binary and installs its command names as symlinks to
//! it (`default.nix` `postInstall`). The binary looks at its own `argv[0]`, runs
//! the matching command, and prints the command list for any other name — the
//! behaviour each crate's `main.rs` used to spell out by hand.

use crate::env;

/// Run the command named by `argv[0]`, or print the list of names and exit 2.
///
/// The table is static, so the lookup costs one `strcmp` per command at
/// startup; nothing here parses arguments or allocates unless the name is
/// unknown.
pub fn dispatch(program: &str, commands: &[(&str, fn())]) -> ! {
    let name = env::prog_name();

    for (command, run) in commands {
        if name == command.as_bytes() {
            run();
            std::process::exit(0);
        }
    }

    fail(program, commands.iter().map(|(command, _)| *command));
}

fn fail<'a>(program: &str, names: impl Iterator<Item = &'a str>) -> ! {
    let mut usage = String::from(program);
    usage.push_str(": invoke one of these names:\n");
    for command in names {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
