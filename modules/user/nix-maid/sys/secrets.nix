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
        "cachix_env" = lib.mkIf (builtins.pathExists "${secretsDir}/cachix.env") {
          format = "dotenv";
          sopsFile = "${secretsDir}/cachix.env";
          path = "/run/user/1000/secrets/cachix.env";
          mode = "0400";
          owner = "neg";
        };
        "github-token" = lib.mkIf (builtins.pathExists "${secretsDir}/github-token.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/github-token.sops.yaml";
          key = "token";
          mode = "0400";
          owner = "neg";
        };
        "vdirsyncer_google_client_id" = lib.mkIf (builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
          key = "client_id";
          owner = "neg";
        };
        "vdirsyncer_google_client_secret" = lib.mkIf (builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
          key = "client_secret";
          owner = "neg";
        };
        "wireguard/work-wg.conf" = lib.mkIf (builtins.pathExists "${secretsDir}/wireguard/work-wg.conf.sops") {
          format = "binary";
          sopsFile = "${secretsDir}/wireguard/work-wg.conf.sops";
          path = "/run/user/1000/secrets/wireguard/work-wg.conf";
          mode = "0600";
          owner = "neg";
        };
        "vless/reality-singbox-tun.json" = lib.mkIf (builtins.pathExists "${secretsDir}/vless/reality-singbox-tun.json.sops") {
          format = "binary";
          sopsFile = "${secretsDir}/vless/reality-singbox-tun.json.sops";
          path = "/run/user/1000/secrets/vless-reality-singbox-tun.json";
          mode = "0600";
          owner = "neg";
        };
        "deepseek-api" = lib.mkIf (builtins.pathExists "${secretsDir}/deepseek-api.sops.yaml") {
          format = "yaml";
          sopsFile = "${secretsDir}/deepseek-api.sops.yaml";
          key = "DEEPSEEK_API_KEY";
          path = "/run/user/1000/secrets/deepseek-api";
          mode = "0400";
          owner = "neg";
        };
      };
    };

  }

]
