{
  lib,
  config,
  ...
}:
with lib;
  mkIf (config.features.mail.enable && config.features.mail.vdirsyncer.enable) (
    let
      templatePath = config.neg.hmConfigRoot + "/modules/user/mail/vdirsyncer/conf/config";
      secretNames = [
        "vdirsyncer/google-client-id"
        "vdirsyncer/google-client-secret"
      ];
      haveSecrets = lib.all (name: config.sops.secrets ? name) secretNames;
    in {
      assertions = [
        {
          assertion = haveSecrets;
          message = ''
            Missing Google OAuth secrets for vdirsyncer.
            Create home/secrets/vdirsyncer/google.sops.yaml with client_id + client_secret.
          '';
        }
      ];

      sops.templates."vdirsyncer-config" = {
        content = builtins.readFile templatePath;
        owner = config.home.username;
        mode = "0600";
      };

      xdg.configFile."vdirsyncer/config".source = config.sops.templates."vdirsyncer-config".path;
    }
  )
