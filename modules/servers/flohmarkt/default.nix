##
# Module: servers/flohmarkt
# Purpose: Flohmarkt — self-hosted small-ads board — for the LAN. The upstream
#          release image and its CouchDB sidecar run as podman containers and
#          the web UI listens on cfg.bindAddress:cfg.port.
# Key options: cfg = config.servicesProfiles.flohmarkt
# Secret: none in the repo or the store. The CouchDB password and the one-time
#         setup code are generated at activation into <dataDir>/{db-password,setup-code}
#         and only ever rendered into <dataDir>/env, which the root-owned
#         containers read at start. The /setup/<code> page at the board's URL
#         creates the first admin account, so bootstrapping does not depend on
#         a working MTA; ordinary registrations still need SMTP (follow-up).
#
# Networking notes: this kernel has no CONFIG_VETH, so podman's netavark bridge
# cannot create veth pairs ("netlink: Operation not supported") and both
# containers run with --network=host instead (the ceno container here does the
# same). Consequences wired up below:
#   * host networking is firewalled like any other host socket, so the board
#     port is opened explicitly unless it stays on loopback;
#   * CouchDB would listen on all interfaces, so the wrapper entrypoint drops a
#     local.d file pinning it to 127.0.0.1 — the web container shares the
#     namespace and reaches it there;
#   * the image's entrypoint hardcodes uvicorn on 0.0.0.0:8000, so the module
#     repeats its config-generation step and listens on bindAddress/port.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg =
    config.servicesProfiles.flohmarkt or {
      enable = false;
      port = 8090;
      bindAddress = "0.0.0.0";
      instanceName = "trantor";
      externalUrl = "http://trantor.local:8090";
      image = "codeberg.org/flohmarkt/flohmarkt:0.20.1";
      dataDir = "/var/lib/flohmarkt";
    };

  envFile = "${cfg.dataDir}/env";

  # Same steps as the image's docker/entrypoint.sh for the "web" command: the
  # generator it calls lives next to it under $FLOHDRVPATH (the nix-built image
  # bakes the source tree in and exports that variable), and the entrypoint's
  # hardcoded 0.0.0.0:8000 gives way to bindAddress/port.
  webCommand = ''
    mkdir -p /etc/flohmarkt
    python3 "''${FLOHDRVPATH:-/}/docker/config_generator.py" > /etc/flohmarkt/flohmarkt.conf
    exec uvicorn --proxy-headers --forwarded-allow-ips='*' \
      --host ${cfg.bindAddress} --port ${toString cfg.port} flohmarkt.web:start --factory
  '';

  # The one-time setup code has to be readable by the human who creates the
  # first account, so the file is owned root:<mainUser's group>.
  mainGroup = config.users.users.${config.lib.neg.mainUser}.group;
in
{
  config = lib.mkIf cfg.enable {
    # Host networking means no implicit podman firewall bypass: the board port
    # has to be allowed explicitly unless it stays on loopback.
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.bindAddress != "127.0.0.1") [ cfg.port ];

    virtualisation.oci-containers.containers = {
      flohmarkt-couchdb = {
        # Named volume, not a bind mount: podman seeds an empty volume from the
        # image, so /opt/couchdb/data ends up with the ownership the couchdb
        # user in the image expects instead of root-owned host directories.
        image = "docker.io/library/couchdb:3.3";
        environmentFiles = [ envFile ];
        volumes = [
          "flohmarkt-couchdb-data:/opt/couchdb/data"
        ];
        # The drop-in carries the loopback bind and `log.level = warning`:
        # CouchDB logs every request at notice level and writes to stderr, so
        # journald files those access lines as priority=err — without the level
        # `journalctl -p err` drowns in `POST /flohmarkt/_find 200 ok`.
        # The drop-in must be written inside the container: the image's
        # entrypoint runs `find /opt/couchdb ... -exec chown ...` over that
        # tree, and with a read-only bind mount that chown fails, aborting the
        # entrypoint (set -e) with no log output and an instant exit 1.
        entrypoint = "/bin/bash";
        cmd = [
          "-c"
          ''
            printf '%s\n' '[chttpd]' 'bind_address = 127.0.0.1' \
              '[log]' 'level = warning' \
              > /opt/couchdb/etc/local.d/90-flohmarkt-bind.ini
            exec /docker-entrypoint.sh couchdb
          ''
        ];
        extraOptions = [ "--network=host" ];
        pull = "missing";
      };

      flohmarkt = {
        image = cfg.image;
        entrypoint = "/bin/bash";
        cmd = [
          "-c"
          webCommand
        ];
        environmentFiles = [ envFile ];
        volumes = [ "${cfg.dataDir}:/var/lib/flohmarkt" ];
        extraOptions = [ "--network=host" ];
        pull = "missing";
        dependsOn = [ "flohmarkt-couchdb" ];
      };
    };

    # The bootstrap is idempotent (create-or-update of databases, users and
    # design docs), which is why the web container only waits for it instead of
    # owning it. The readiness probe runs inside the CouchDB container because
    # the database is pinned to loopback.
    systemd.services.flohmarkt-initdb = {
      description = "Flohmarkt CouchDB bootstrap (databases, user, design docs)";
      after = [ "podman-flohmarkt-couchdb.service" ];
      requires = [ "podman-flohmarkt-couchdb.service" ];
      # Behind post-boot: the bootstrap waited on CouchDB on the critical path
      # to graphical.target (see the deferral note further down).
      wantedBy = [ "post-boot.target" ];
      path = [
        pkgs.coreutils # seq and sleep in the readiness loop
        pkgs.curl # the readiness probe's curl, run inside the CouchDB container
        pkgs.podman # podman exec/run: probe and initdb stay in the host network
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        for _ in $(seq 1 90); do
          podman exec flohmarkt-couchdb curl -fsS http://127.0.0.1:5984/ >/dev/null 2>&1 && break
          sleep 2
        done
        podman run --rm --network host --env-file ${envFile} \
          -v ${cfg.dataDir}:/var/lib/flohmarkt ${cfg.image} initdb
      '';
    };

    systemd.services.podman-flohmarkt = {
      after = [ "flohmarkt-initdb.service" ];
      wants = [ "flohmarkt-initdb.service" ];
    };

    # The board is not needed for a login: CouchDB plus the initdb bootstrap sat
    # on the critical path to graphical.target (~3 s: initdb alone waits up to
    # 2.5 s for CouchDB), so the three units move behind post-boot.target
    # (modules/system/systemd/post-boot.nix). They still pull each other in.
    systemd.services = {
      "podman-flohmarkt-couchdb".wantedBy = lib.mkForce [ "post-boot.target" ];
      podman-flohmarkt.wantedBy = lib.mkForce [ "post-boot.target" ];
    };

    # Secrets stay host-local by design: only the two generated values ever
    # reach the env file, and neither passes through the nix store. The file is
    # re-rendered on every activation while the generated values persist, so the
    # containers keep the same credentials across switches.
    #
    # The body runs in a subshell: NixOS concatenates every activation snippet
    # into one shell, so a bare `umask 077` here would still be in effect for
    # every later snippet — setupSecrets (sops) comes after this one and its
    # per-generation /run/secrets.d/N is created with mkdir, which yields 0700
    # under umask 077 instead of 0751. That made every non-root secret reader
    # fail with EACCES (mpdas, listenbrainz-mpd, ...).
    system.activationScripts.flohmarkt = lib.stringAfter [ "var" ] ''
      (
      # Directory group-read for the main user is what makes <dataDir>/setup-code
      # reachable (the code is 0640 root:<group>); the two secret files inside
      # stay 0600/0640 owned by root and are never world-readable.
      ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g ${mainGroup} ${cfg.dataDir}
      if [ ! -s ${cfg.dataDir}/db-password ]; then
        umask 077
        ${lib.getExe pkgs.openssl} rand -hex 24 > ${cfg.dataDir}/db-password
      fi
      if [ ! -s ${cfg.dataDir}/setup-code ]; then
        umask 077
        ${lib.getExe pkgs.openssl} rand -hex 8 > ${cfg.dataDir}/setup-code
      fi
      ${pkgs.coreutils}/bin/chown root:${mainGroup} ${cfg.dataDir}/setup-code
      ${pkgs.coreutils}/bin/chmod 0640 ${cfg.dataDir}/setup-code

      umask 077
      {
        printf '%s\n' \
          'LANG=en_US.UTF-8' \
          'FLOHMARKT_INSTANCE_NAME=${cfg.instanceName}' \
          'FLOHMARKT_EXTERNAL_URL=${cfg.externalUrl}' \
          'FLOHMARKT_DATA_PATH=/var/lib/flohmarkt' \
          'FLOHMARKT_DB_HTTPS=0' \
          'FLOHMARKT_DB_HOST=127.0.0.1' \
          'FLOHMARKT_DB_PORT=5984' \
          'FLOHMARKT_DB_NAME=flohmarkt' \
          'FLOHMARKT_DB_USER=admin' \
          "FLOHMARKT_DB_PASSWORD=$(${pkgs.coreutils}/bin/cat ${cfg.dataDir}/db-password)" \
          "FLOHMARKT_SETUPCODE=$(${pkgs.coreutils}/bin/cat ${cfg.dataDir}/setup-code)" \
          'FLOHMARKT_MAIL_METHOD=sendmail' \
          'FLOHMARKT_MAIL_FROM=flohmarkt@trantor.local' \
          'FLOHMARKT_SMTP_SERVER=' \
          'FLOHMARKT_SMTP_PORT=25' \
          'FLOHMARKT_SMTP_USER=' \
          'FLOHMARKT_SMTP_PASSWORD=' \
          'FLOHMARKT_SMTP_CAFILE=' \
          'FLOHMARKT_SMTP_NOVERIFYCERT=0' \
          'FLOHMARKT_TILECACHE_SERVER_URL=https://tile.openstreetmap.org' \
          'FLOHMARKT_TILECACHE_SIZE=10_000' \
          'COUCHDB_USER=admin' \
          "COUCHDB_PASSWORD=$(${pkgs.coreutils}/bin/cat ${cfg.dataDir}/db-password)"
      } > ${envFile}.new
      ${pkgs.coreutils}/bin/mv ${envFile}.new ${envFile}
      )
    '';
  };
}
