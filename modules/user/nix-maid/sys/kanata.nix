# Module: nix-maid/sys/kanata — deploys the kanata config file.
#
# The kanata systemd user service (modules/hardware/input/default.nix) runs
# `kanata --cfg %h/.config/kanata/kanata.kbd`; without this file the remapper
# exits on startup. Config source: files/cli/kanata/kanata.kbd.
# Feature flag: features.input.kanata.enable (declared in features/hardware.nix).
{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.features.input.kanata.enable or false) (
    neg.mkHomeFiles {
      ".config/kanata/kanata.kbd".source = config.lib.neg.path "files/cli/kanata/kanata.kbd";
    }
  );
}
