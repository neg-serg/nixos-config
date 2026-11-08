##
# Module: servers/searx
# Purpose: SearXNG self-hosted metasearch, bound to localhost as the default
#          privacy-first search for Vivaldi.
# Key options: cfg = config.servicesProfiles.searx.enable
# Secret: sops secrets/home/searxng.sops.yaml["searxng-secret"] = a single
#         "SEARX_SECRET_KEY=<value>" line (read via services.searx.environmentFile).
# On-demand: the 347 MiB Python closure of searxng is a GC root
#         (/var/lib/nix-apps/searx), not part of the system image. The unit runs
#         as a DynamicUser that cannot fetch the flake, so `searx-ensure`
#         (oneshot, main user) materialises the root before `searx.service`, and
#         ExecStart points into that root. Refresh after a flake update:
#             nix-apps update searx && sudo systemctl restart searx
#         (nix-apps.sh maps the root name `searx` to the `searxng` flake attr).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.servicesProfiles.searx or { enable = false; };

  onDemand = config.lib.neg.onDemand pkgs;
  # `searx` on PATH: the package's only binary is `searxng-run`, and the root
  # name matches the systemd unit so `nix-apps update searx` prints the right
  # restart hint.
  searxLauncher = onDemand {
    name = "searx";
    attr = "searxng";
    binary = "searxng-run";
  };

  nixAppsRoot = "/var/lib/nix-apps";
  searxRoot = "${nixAppsRoot}/searx";
  searxEnsure = pkgs.writeShellScriptBin "searx-ensure" ''
    set -eu
    root=${lib.escapeShellArg searxRoot}
    if [ -e "$root" ]; then
      exit 0
    fi
    mkdir -p ${nixAppsRoot}
    rm -f "$root"
    out=$(${config.nix.package}/bin/nix build --no-link --print-out-paths 'git+file:///etc/nixos#searxng')
    ${config.nix.package}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
  '';
in
{
  config = lib.mkIf cfg.enable {
    # systemd (root) reads EnvironmentFile, so a root-owned 0400 sops secret
    # is fine for this system service.
    sops.secrets."searxng-secret" = {
      sopsFile = config.lib.neg.path "secrets/home/searxng.sops.yaml";
      owner = "root";
      mode = "0400";
    };

    services.searx = {
      enable = true;
      package = searxLauncher; # on PATH only; the service runs the GC-root build
      # File content must be: SEARX_SECRET_KEY=<value>  (see sops entry above).
      environmentFile = config.sops.secrets."searxng-secret".path;
      settings = {
        server = {
          secret_key = "@SEARX_SECRET_KEY@";
          bind_address = "127.0.0.1";
          port = 7777;
          # Localhost-only instance behind no reverse proxy: botdetection would
          # log "X-Forwarded-For nor X-Real-IP header is set!" on every request.
          limiter = false;
        };
        search = {
          formats = [
            "html"
            "json"
          ];
        };
        # torch and ahmia need a Tor proxy that is not configured here, so they
        # fail at startup and flood the journal ("set engine to inactive").
        engines = [
          {
            name = "torch";
            disabled = true;
          }
          {
            name = "ahmia";
            disabled = true;
          }
        ];
      };
    };

    systemd.services.searx-ensure = {
      description = "Materialise the on-demand searx root (GC root at /var/lib/nix-apps)";
      wantedBy = [ "multi-user.target" ];
      before = [ "searx.service" ];
      after = [
        "network.target"
        "systemd-tmpfiles-setup.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = config.lib.neg.mainUser;
      };
      script = "${searxEnsure}/bin/searx-ensure";
    };

    systemd.services.searx = {
      wants = [ "searx-ensure.service" ];
      after = [ "searx-ensure.service" ];
      serviceConfig.ExecStart = lib.mkForce "${searxRoot}/bin/searxng-run";
    };
  };
}
