{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;
  cfg = config.vivaldi.codexStellarium;

  # Built from the flake input (not from system pkgs).
  # inputs.codex-stellarium reaches through specialArgs.
  extPkg = import "${inputs.codex-stellarium}/pkgs/codex-stellarium-vivaldi" { inherit (pkgs) stdenvNoCC lib; };
in {
  options.vivaldi.codexStellarium = {
    enable = mkEnableOption "Codex-Stellarium newtab page for Vivaldi";

    user = mkOption {
      type = types.str;
      default = "neg";
      description = "Linux username to install the extension for.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ extPkg ];

    # System tmpfiles: create parent dir with correct owner first,
    # then the symlink inside it. Without `d` — unsafe path transition,
    # because ~/.local/share/ is owned by the user while tmpfiles runs as root.
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.local/share/codex-stellarium 0755 ${cfg.user} users -"
      "L+ /home/${cfg.user}/.local/share/codex-stellarium/vivaldi - - - - ${extPkg}/share/codex-stellarium-vivaldi"
    ];
  };
}
