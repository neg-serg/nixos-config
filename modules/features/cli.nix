{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.cli = {
    fastCnf.enable = mkBool "enable fast zsh command-not-found handler powered by nix-index" true;
    yandexCloud.enable = mkBool "enable Yandex Cloud CLI" false;
    broot.enable = mkBool "enable broot file manager and shell integration" false;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
    bsh.enable = mkBool "enable BSH (Better Shell History) - Git-aware predictive terminal history" true;

    television.enable = mkBool "enable television (blazingly fast fuzzy finder)" true;
    zcli = {
      enable = mkBool "install zcli helper for nh-based flake switches" false;
      profile = mkOption {
        type = types.str;
        default = "telfir";
        description = "Profile/hostname passed to nh os switch --hostname.";
        example = "telfir";
      };
      repoRoot = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional override for the repository root; defaults to the configured neg.repoRoot.";
      };
      flakePath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional override for the flake.nix path if it is not under repoRoot.";
      };
      backupFiles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Relative paths under $HOME that zcli should report as pre-existing backups.";
        example = [ ".config/mimeapps.list.backup" ];
      };
    };
  };
}
