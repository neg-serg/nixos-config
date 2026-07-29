{
  lib,
  config,
  ...
}:
let
  secretsDir = ../../../../secrets/home;
in
lib.mkMerge [
  {
    sops = {
      age.keyFile = lib.mkForce "${config.users.users.neg.home}/.config/sops/age/keys.txt";
      defaultSopsFile = "${secretsDir}/all.yaml";
      secrets = {
        # github-netrc, mpdas, musicbrainz are managed elsewhere
        "github-token" = lib.mkIf (builtins.pathExists "${secretsDir}/github-token.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/github-token.sops.yaml";
          key = "token";
          mode = "0400";
          owner = "neg";
        };
        "vdirsyncer_google_client_id" =
          lib.mkIf (builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml")
            {
              format = "yaml";
              sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
              key = "client_id";
              owner = "neg";
            };
        "vdirsyncer_google_client_secret" =
          lib.mkIf (builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml")
            {
              format = "yaml";
              sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
              key = "client_secret";
              owner = "neg";
            };
      };
    };

  }

]
