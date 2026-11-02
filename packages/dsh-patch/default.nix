##
# Package: dsh-patch
# Purpose: The exact-string, count-asserted patcher for dsh. The build-time
#   subcommands (widgets, session-format, session-migration, ptc-env) apply the
#   bundle patches after npm install; the caretaker subcommands
#   (models-settings, tui-preset, liangshen-prune) rewrite the terminal
#   profile's cordis.patch.yml, the liangshen preset and ~/.dsh/settings.yaml.
#   A replacement that does not match the expected number of times aborts
#   instead of shipping a half-patched tree.
#
# Port of packages/dsh/lib/patchlib.py, packages/dsh/patch-*.py and
# modules/user/nix-maid/apps/dsh-{models-settings,tui-preset-patch,
# tui-liangshen-prune}.py; output-compatible with them.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "dsh-patch";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Count-asserted exact-string patcher for dsh bundles and profiles";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "dsh-patch";
  };
}
