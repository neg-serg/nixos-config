//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

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
    multicall::dispatch("local-bin-audio", COMMANDS);
}
