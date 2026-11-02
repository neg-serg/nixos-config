##
# Package: swayimg-actions
# Purpose: move/copy/rotate/wallpaper/range actions for swayimg — the Rust port
#   of the former packages/local-bin/bin/swayimg-actions.sh zsh helper. It keeps
#   the CLI, exit codes, diagnostics, destination picker, IPC handshake, range
#   anchoring and wallpaper pipeline of the shell version; the external tools
#   (mogrify/convert/swww/swaymsg/vicinae/zoxide/wl-copy/pic-notify, plus the
#   coreutils calls whose messages are observable) are still spawned exactly as
#   before.
#
#   The shell-specific plumbing is replaced natively:
#   - socat/ncat IPC -> a UnixStream against $SWAYIMG_IPC or the newest
#     swayimg-*.sock in $XDG_RUNTIME_DIR;
#   - `swaymsg -t get_outputs -r | jq` -> serde_json (the jq dependency and its
#     output-formatting quirks are gone);
#   - find/sort/awk/sed path listings -> byte-wise directory walks and a sort by
#     ctime, so the result no longer depends on the ambient locale.
#
#   `cargo test` is offline and hermetic: a temp HOME/XDG tree, fake tools on
#   PATH, fixture images with controlled ctimes and a real UnixListener socket
#   for the IPC bytes. `tests/parity/` is the one-off migration harness that
#   compares this binary with the zsh script while the script still exists;
#   cargo does not run it.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "swayimg-actions";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Rotate/move/copy/wallpaper/range actions for swayimg";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "swayimg-actions";
  };
}
