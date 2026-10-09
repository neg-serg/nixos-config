# Module: nix-maid/sys/neru — deploys the neru config file.
#
# The neru systemd user service (modules/user/session/neru.nix) runs
# `neru launch --config %h/.config/neru/config.toml`; without this file neru
# falls back to built-in defaults, which carry no hotkeys on Linux.
# Config source: files/neru/config.toml.
# Feature flag: features.input.neru.enable (declared in features/hardware.nix).
{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.features.input.neru.enable or false) (
    neg.mkHomeFiles {
      ".config/neru/config.toml".source = config.lib.neg.live "files/neru/config.toml";
    }
  );
}
