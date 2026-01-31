{
  lib,
  config,
  ...
}:
let
  secretsDir = ../../../../secrets/home;
  hasGitHubToken = builtins.pathExists "${secretsDir}/github-token.sops.yaml";
  hasCachixEnv = builtins.pathExists "${secretsDir}/cachix.env";
  hasVdirsyncerGoogle = builtins.pathExists "${secretsDir}/vdirsyncer/google.sops.yaml";
  hasWorkWireguard = builtins.pathExists "${secretsDir}/wireguard/work-wg.conf.sops";
  hasVlessRealitySingboxTun = builtins.pathExists "${secretsDir}/vless/reality-singbox-tun.json.sops";
  hasBraveSearchApi = builtins.pathExists "${secretsDir}/brave-search-api.env.sops";
  hasContext7Api = builtins.pathExists "${secretsDir}/context7-api.env.sops";
in
{
  sops = {
    age.keyFile = lib.mkForce "${config.users.users.neg.home}/.config/sops/age/keys.txt";
    defaultSopsFile = "${secretsDir}/all.yaml";
    secrets = {
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
      "vdirsyncer_google_client_id" = {
        format = "yaml";
        sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
        key = "client_id";
        owner = "neg";
      };
      "vdirsyncer_google_client_secret" = {
        format = "yaml";
        sopsFile = "${secretsDir}/vdirsyncer/google.sops.yaml";
        key = "client_secret";
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
    }
    // lib.optionalAttrs hasBraveSearchApi {
      "brave-search-api-env" = {
        format = "binary";
        sopsFile = "${secretsDir}/brave-search-api.env.sops";
        path = "/run/user/1000/secrets/brave-search-api.env";
        mode = "0400";
        owner = "neg";
      };
    }
    // lib.optionalAttrs hasContext7Api {
      "context7-api-env" = {
        format = "binary";
        sopsFile = "${secretsDir}/context7-api.env.sops";
        path = "/run/user/1000/secrets/context7-api.env";
        mode = "0400";
        owner = "neg";
      };
    };
  };
}
