//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary.
//! Running the binary under any other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_audio::{
    audio_diag, flacspec, jam, midi_bridge, mp, nb, qe, renoise_osc_config, sc_live, sc_record,
    shabda, synth,
};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("audio-diag", audio_diag::entry),
    ("jam", jam::entry),
    ("shabda", shabda::entry),
    ("synth", synth::entry),
    ("midi-bridge", midi_bridge::entry),
    ("renoise-osc-config", renoise_osc_config::entry),
    ("sc-live", sc_live::entry),
    ("sc-record", sc_record::entry),
    ("flacspec", flacspec::entry),
    ("mp", mp::entry),
    ("nb", nb::entry),
    ("qe", qe::entry),
];

fn main() {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    let name = Path::new(&argv0)
        .file_name()
        .map(OsStr::to_owned)
        .unwrap_or_default();

    for (command, run) in COMMANDS {
        if OsStr::new(command) == name {
            run();
            return;
        }
    }

    let mut usage = String::from("local-bin-audio: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
