//! Help and usage texts of the ported scripts.
//!
//! The shell originals printed these by `sed`-ing their own comment header
//! (the header lines are part of the installed script), so the exact bytes live
//! here. They are byte-for-byte the output of the original commands; the parity
//! harness compares them against the scripts directly.

/// `flacspec`: `_localbin.sh` `help_from_header 2 2`.
pub const FLACSPEC_USAGE: &str =
    "flacspec: generate spectrograms for all .flac in current directory\n";

/// `mp`: `_localbin.sh` `help_from_header 2 4`.
pub const MP_USAGE: &str = r##"mp: play with mpv and print media info for inputs concurrently
Usage: mp FILES...
  Spawns vid-info for provided files/dirs and plays them via mpv.
"##;

/// `nb -h|--help`: the script prints this one line on **stderr** and exits 0.
pub const NB_HELP: &str = "nb: update notes and push if changed\n";
