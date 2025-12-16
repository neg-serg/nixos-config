{lib, ...}: let
  secretsDir = ../../../secrets/home;
  hasGitHubToken = builtins.pathExists "${secretsDir}/github-token.sops.yaml";
  hasCachixEnv = builtins.pathExists "${secretsDir}/cachix.env";
  hasVdirsyncerGoogle = builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml";
  hasNextcloudWork = builtins.pathExists "${secretsDir}/nextcloud-cli-wrk.env.sops";
  hasWorkWireguard = builtins.pathExists "${secretsDir}/wireguard/work-wg.conf.sops";
  hasVlessRealitySingboxTun = builtins.pathExists "${secretsDir}/vless/reality-singbox-tun.json.sops";
in {
  sops = {
    age.keyFile = lib.mkForce "/home/neg/.config/sops/age/keys.txt";
    defaultSopsFile = "${secretsDir}/all.yaml";
    secrets =
      {
        # github-netrc, mpdas, musicbrainz are managed elsewhere
      }
      // lib.optionalAttrs hasCachixEnv {
        "cachix_env" = {
          format = "dotenv";
          sopsFile = "${secretsDir}/cachix.env";
          path = "/run/user/1000/secrets/cachix.env";
          mode = "0400";
          owner = "neg";
        };
      }
      // lib.optionalAttrs hasGitHubToken {
        "github-token" = {
          format = "yaml";
          sopsFile = "${secretsDir}/github-token.sops.yaml";
          key = "token";
          mode = "0400";
          owner = "neg";
        };
      }
      // lib.optionalAttrs hasVdirsyncerGoogle {
        "vdirsyncer/google-client-id" = {
          format = "yaml";
          sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
          key = "client_id";
          owner = "neg";
        };
        "vdirsyncer/google-client-secret" = {
          format = "yaml";
          sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
          key = "client_secret";
          owner = "neg";
        };
      }
      // {
        "nextcloud-cli/env" = {
          format = "dotenv";
          sopsFile = "${secretsDir}/nextcloud-cli.env.sops";
          path = "/run/user/1000/secrets/nextcloud-cli.env";
          mode = "0400";
          owner = "neg";
        };
      }
      // lib.optionalAttrs hasNextcloudWork {
        "nextcloud-cli-wrk/env" = {
          format = "dotenv";
          sopsFile = "${secretsDir}/nextcloud-cli-wrk.env.sops";
          path = "/run/user/1000/secrets/nextcloud-cli-wrk.env";
          mode = "0400";
          owner = "neg";
        };
      }
      // lib.optionalAttrs hasWorkWireguard {
        "wireguard/work-wg.conf" = {
          format = "binary";
          sopsFile = "${secretsDir}/wireguard/work-wg.conf.sops";
          path = "/run/user/1000/secrets/wireguard/work-wg.conf";
          mode = "0600";
          owner = "neg";
        };
      }
      // lib.optionalAttrs hasVlessRealitySingboxTun {
        "vless/reality-singbox-tun.json" = {
          format = "binary";
          sopsFile = "${secretsDir}/vless/reality-singbox-tun.json.sops";
          path = "/run/user/1000/secrets/vless-reality-singbox-tun.json";
          mode = "0600";
          owner = "neg";
        };
      };
  };
}
