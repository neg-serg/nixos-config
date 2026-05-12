{
  lib,
  config,
  pkgs,
  ...
}:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  enabled = config.roles.media.enable or false;

  deepfacelabRoot = "${homeDir}/vid/deepfacelab";
  dataDir = "${deepfacelabRoot}/data";
  repoDir = "${deepfacelabRoot}/repo";

  deepfacelabDocker = pkgs.writeShellScriptBin "deepfacelab-docker" (
    lib.replaceStrings [ "@repoDir@" "@dataDir@" ] [ repoDir dataDir ] (
      builtins.readFile ./scripts/deepfacelab-docker.sh
    )
  );
in
{
  config = lib.mkIf (enabled && (config.features.virt.docker.enable or false)) {
    environment.systemPackages = lib.mkAfter [
      deepfacelabDocker # helper to launch DeepFaceLab Ubuntu Docker container
    ];

    systemd.tmpfiles.rules = [
      "d ${deepfacelabRoot} 0750 ${mainUser} ${mainUser} -"
      "d ${dataDir} 0750 ${mainUser} ${mainUser} -"
      "d ${repoDir} 0750 ${mainUser} ${mainUser} -"
    ];
  };
}
