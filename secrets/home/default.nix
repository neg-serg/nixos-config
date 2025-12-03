{
  config,
  lib,
  ...
}: let
  hasGitHubToken = builtins.pathExists ./github-token.sops.yaml;
  hasCachixEnv = builtins.pathExists ./cachix.env;
  hasVdirsyncerGoogle = builtins.pathExists ./vdirsyncer/google.sops.yaml;
  hasNextcloudWork = builtins.pathExists ./nextcloud-cli-wrk.env.sops;
  hasWorkWireguard = builtins.pathExists ./wireguard/work-wg.conf.sops;
  hasVlessRealitySingbox = builtins.pathExists ./vless/reality-singbox.json.sops;
  hasVlessRealityXray = builtins.pathExists ./vless/reality-xray.json.sops;
in {
  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    defaultSopsFile = ./all.yaml;
    secrets =
      {
        # Netrc for GitHub to avoid rate limits in fetchers
        "github-netrc" = {
          format = "yaml";
          sopsFile = ./github-netrc.sops.yaml;
          key = "github-netrc";
          path = "${config.xdg.configHome}/nix/netrc";
          mode = "0400";
        };
        "mpdas_negrc" = {
          format = "binary";
          sopsFile = ./mpdas/neg.rc;
          path = "/run/user/1000/secrets/mpdas_negrc";
        };
        "musicbrainz.yaml" = {
          format = "binary";
          sopsFile = ./musicbrainz;
          path = "/run/user/1000/secrets/musicbrainz.yaml";
        };
        # Cachix token for watch-store user service (systemd EnvironmentFile format)
        # Included only if secrets/cachix.env exists in the repo.
        # Create and encrypt this file with sops; contents must be a single line:
        #   CACHIX_AUTH_TOKEN=...
      }
      // lib.optionalAttrs hasCachixEnv {
        "cachix_env" = {
          format = "dotenv";
          sopsFile = ./cachix.env;
          path = "/run/user/1000/secrets/cachix.env";
          mode = "0400";
        };
      }
      // lib.optionalAttrs hasGitHubToken {
        # Optional: personal GitHub token for Nix access-tokens
        "github-token" = {
          format = "yaml";
          sopsFile = ./github-token.sops.yaml;
          key = "token";
          mode = "0400";
        };
      }
      // lib.optionalAttrs hasVdirsyncerGoogle {
        "vdirsyncer/google-client-id" = {
          format = "yaml";
          sopsFile = ./vdirsyncer/google.sops.yaml;
          key = "client_id";
        };
        "vdirsyncer/google-client-secret" = {
          format = "yaml";
          sopsFile = ./vdirsyncer/google.sops.yaml;
          key = "client_secret";
        };
      }
      // {
        # NEXTCLOUD_PASS=... for nextcloudcmd (user-level sync service)
        "nextcloud-cli/env" = {
          format = "dotenv";
          sopsFile = ./nextcloud-cli.env.sops;
          path = "/run/user/1000/secrets/nextcloud-cli.env";
          mode = "0400";
        };
      }
      // lib.optionalAttrs hasNextcloudWork {
        # Work profile: NEXTCLOUD_URL, NEXTCLOUD_USER, NEXTCLOUD_PASS
        "nextcloud-cli-wrk/env" = {
          format = "dotenv";
          sopsFile = ./nextcloud-cli-wrk.env.sops;
          path = "/run/user/1000/secrets/nextcloud-cli-wrk.env";
          mode = "0400";
        };
      }
      // lib.optionalAttrs hasWorkWireguard {
        # WireGuard/AmneziaWG config for work tunnel (wg-quick/awg-quick compatible)
        "wireguard/work-wg.conf" = {
          format = "binary";
          sopsFile = ./wireguard/work-wg.conf.sops;
          path = "/run/user/1000/secrets/wireguard/work-wg.conf";
          mode = "0600";
        };
      }
      // lib.optionalAttrs hasVlessRealitySingbox {
        # VLESS Reality config (sing-box)
        "vless/reality-singbox.json" = {
          format = "binary";
          sopsFile = ./vless/reality-singbox.json.sops;
          path = "/run/user/1000/secrets/vless-reality-singbox.json";
          mode = "0600";
        };
      }
      // lib.optionalAttrs hasVlessRealityXray {
        # VLESS Reality config (Xray)
        "vless/reality-xray.json" = {
          format = "binary";
          sopsFile = ./vless/reality-xray.json.sops;
          path = "/run/user/1000/secrets/vless-reality-xray.json";
          mode = "0600";
        };
      };
  };

  # Note: we intentionally avoid writing access tokens to nix.conf.
  # Authentication is handled via the sops-managed netrc referenced by nix.settings.netrc-file.
}
