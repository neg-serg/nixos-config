{
  config,
  lib,
  ...
}:
let
  hasGitHubToken = builtins.pathExists ./github-token.sops.yaml;
  hasCachixEnv = builtins.pathExists ./cachix.env;
  hasVdirsyncerGoogle = builtins.pathExists ./vdirsyncer/google.sops.yaml;
  hasWorkWireguard = builtins.pathExists ./wireguard/work-wg.conf.sops;
  hasVlessRealitySingboxTun = builtins.pathExists ./vless/reality-singbox-tun.json.sops;
  hasBraveSearchApi = builtins.pathExists ./brave-search-api.env.sops;
in
{
  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    defaultSopsFile = ./all.yaml;
    secrets = {
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
    // lib.optionalAttrs hasWorkWireguard {
      # WireGuard/AmneziaWG config for work tunnel (wg-quick/awg-quick compatible)
      "wireguard/work-wg.conf" = {
        format = "binary";
        sopsFile = ./wireguard/work-wg.conf.sops;
        path = "/run/user/1000/secrets/wireguard/work-wg.conf";
        mode = "0600";
      };
    }
    // lib.optionalAttrs hasVlessRealitySingboxTun {
      # VLESS Reality config (sing-box, TUN/full-tunnel)
      "vless/reality-singbox-tun.json" = {
        format = "binary";
        sopsFile = ./vless/reality-singbox-tun.json.sops;
        path = "/run/user/1000/secrets/vless-reality-singbox-tun.json";
        mode = "0600";
      };
    }
    // lib.optionalAttrs hasBraveSearchApi {
      # Brave Search API key for MCP server (environment file format)
      "brave-search-api-env" = {
        format = "dotenv";
        sopsFile = ./brave-search-api.env.sops;
        path = "/run/user/1000/secrets/brave-search-api.env";
        mode = "0400";
      };
    };
  };

  # Note: we intentionally avoid writing access tokens to nix.conf.
  # Authentication is handled via the sops-managed netrc referenced by nix.settings.netrc-file.
}
