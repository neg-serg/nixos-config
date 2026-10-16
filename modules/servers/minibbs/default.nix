##
# Module: servers/minibbs
# Purpose: minibbs — a tiny BBS-style board for the LAN. Boards hold threads,
#          threads hold posts; bots write through the bearer-token JSON API and
#          humans read the read-only web UI (HTML, or `?fmt=txt` for a plain
#          text view). Storage is one SQLite file; the app itself is stdlib-only
#          Python in files/minibbs/minibbs.py.
# Key options: cfg = config.servicesProfiles.minibbs
# Secret: none in the repo or the store — the bearer token is generated at
#         activation into <dataDir>/token (0640 root:minibbs) and re-read on
#         every request, so rotating it needs no restart. The main user is added
#         to the minibbs group so their scripts can read the same token.
# Bot example:
#   curl -sS -X POST http://trantor.local:8091/api/post \
#     -H "Authorization: Bearer $(cat /var/lib/minibbs/token)" \
#     -H 'Content-Type: application/json' \
#     -d '{"board":"alerts","author":"crashloop","subject":"MPD restarted","body":"..."}'
# Append to a thread by adding "thread": <id> and dropping "subject".
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg =
    config.servicesProfiles.minibbs or {
      enable = false;
      port = 8091;
      bindAddress = "0.0.0.0";
      title = "trantor BBS";
      dataDir = "/var/lib/minibbs";
    };

  app = config.lib.neg.path "files/minibbs/minibbs.py";

  # Posting helper shared by the host's bots (hosts/trantor/notify-*). It stays
  # non-fatal on purpose: a board that is down must never break a notifier.
  # MINIBBS_URL / MINIBBS_TOKEN_FILE override the baked-in defaults (tests).
  minibbsPost = pkgs.writeShellApplication {
    name = "minibbs-post";
    runtimeInputs = [
      pkgs.curl # HTTP client the posting helper uses for the board's JSON API
      pkgs.jq # builds the JSON payload, keeping the quoting out of the shell
    ];
    text = ''
      # usage: minibbs-post <board> <author> [subject]  (body on stdin)
      board="''${1:?usage: minibbs-post <board> <author> [subject]}"
      author="''${2:?usage: minibbs-post <board> <author> [subject]}"
      subject="''${3:-}"
      body="$(cat)"
      if [ -z "$body" ]; then
        echo "minibbs-post: empty body, nothing to post" >&2
        exit 0
      fi
      payload="$(jq -n --arg b "$board" --arg a "$author" --arg s "$subject" --arg t "$body" \
        '{board: $b, author: $a, body: $t} + (if $s == "" then {} else {subject: $s} end)')"
      url="''${MINIBBS_URL:-http://127.0.0.1:${toString cfg.port}}/api/post"
      token_file="''${MINIBBS_TOKEN_FILE:-${cfg.dataDir}/token}"
      token="$(cat "$token_file" 2> /dev/null || true)"
      if [ -z "$token" ]; then
        echo "minibbs-post: no token at $token_file" >&2
        exit 0
      fi
      curl -fsS -m 10 -X POST "$url" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        -d "$payload" > /dev/null \
        || echo "minibbs-post: could not reach $url" >&2
      exit 0
    '';
  };

  # Module-shaped systemd units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ minibbsPost ];
    # Other modules (the notifiers) reach the same helper through this option.
    servicesProfiles.minibbs.postCommand = minibbsPost;
    # Host networking is not involved here (plain systemd service), so this is
    # the only firewall line that matters on a host without a mkForce override.
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.bindAddress != "127.0.0.1") [ cfg.port ];

    users.users.minibbs = {
      isSystemUser = true;
      group = "minibbs";
      home = cfg.dataDir;
      description = "minibbs board service";
    };
    users.groups.minibbs = { };
    # The token is root:minibbs 0640 — group membership is what lets the owner's
    # own scripts post without sudo.
    users.users.${config.lib.neg.mainUser}.extraGroups = [ "minibbs" ];

    systemd.services.minibbs = systemdUser.mkSystemService {
      description = "minibbs BBS-style message board";
      presets = [ "restartOnFailure" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        # The app is a store path; never try to write bytecode next to it.
        PYTHONDONTWRITEBYTECODE = "1";
        MINIBBS_DB = "${cfg.dataDir}/bbs.sqlite";
        MINIBBS_TOKEN_FILE = "${cfg.dataDir}/token";
        MINIBBS_BIND = cfg.bindAddress;
        MINIBBS_PORT = toString cfg.port;
        MINIBBS_TITLE = cfg.title;
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${app}";
        User = "minibbs";
        Group = "minibbs";
        # A crash should not take the board down for good; the restartOnFailure
        # preset supplies Restart=on-failure (the crash-loop scanner only
        # considers units systemd is told to restart), the delay stays here.
        RestartSec = 10;
        ProtectSystem = "strict";
        ProtectHome = true;
        # ProtectSystem=strict mounts /var read-only, so the SQLite database
        # needs an explicit writable carve-out; everything else stays read-only.
        ReadWritePaths = [ cfg.dataDir ];
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = "";
        LockPersonality = true;
      };
    };

    # The state directory belongs to the service user, but the main user needs
    # to traverse it to read the token, hence the group.
    system.activationScripts.minibbs = lib.stringAfter [ "var" ] ''
      ${pkgs.coreutils}/bin/install -d -m 0750 -o minibbs -g minibbs ${cfg.dataDir}
      if [ ! -s ${cfg.dataDir}/token ]; then
        umask 077
        ${lib.getExe pkgs.openssl} rand -hex 24 > ${cfg.dataDir}/token
      fi
      ${pkgs.coreutils}/bin/chown root:minibbs ${cfg.dataDir}/token
      ${pkgs.coreutils}/bin/chmod 0640 ${cfg.dataDir}/token
    '';
  };
}
