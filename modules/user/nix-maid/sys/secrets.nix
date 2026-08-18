{
  lib,
  config,
  ...
}:
let
  secretsDir = config.lib.neg.path "secrets/home";
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
        "proxy-fallback" = lib.mkIf (builtins.pathExists "${secretsDir}/proxy-fallback.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/proxy-fallback.sops.yaml";
          key = "fallback_nodes";
          mode = "0400";
          owner = "neg";
        };
        # LAN SOCKS5 proxy credentials (sing-box in-lan inbound, port 10810):
        # "username:password", read by ~/.local/bin/proxy at config generation.
        "proxy-lan" = lib.mkIf (builtins.pathExists "${secretsDir}/proxy-lan.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/proxy-lan.sops.yaml";
          key = "credentials";
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
        "deepseek-api" = lib.mkIf (builtins.pathExists "${secretsDir}/deepseek-api.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/deepseek-api.sops.yaml";
          key = "DEEPSEEK_API_KEY";
          mode = "0400";
          owner = "neg";
        };
      };
    };

  }

]
