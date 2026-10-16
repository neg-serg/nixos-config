##
# Module: servers/flohmarkt
# Purpose: Flohmarkt — self-hosted small-ads board — for the LAN. The upstream
#          release image and its CouchDB sidecar run as podman containers, and
#          the web UI is published on cfg.bindAddress:cfg.port. Publishing a
#          container port bypasses the NixOS firewall, so the bind address is
#          the only exposure knob.
# Key options: cfg = config.servicesProfiles.flohmarkt
# Secret: none in the repo or the store. The CouchDB password and the one-time
#         setup code are generated at activation into <dataDir>/{db-password,setup-code}
#         and only ever rendered into <dataDir>/env, which the root-owned
#         containers read at start. The /setup/<code> page at the board's URL
#         creates the first admin account, so bootstrapping does not depend on
#         a working MTA; ordinary registrations still need SMTP (follow-up).
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

  # The one-time setup code has to be readable by the human who creates the
  # first account, so the file is owned root:<mainUser's group>.
  mainGroup = config.users.users.${config.lib.neg.mainUser}.group;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      flohmarkt-couchdb = {
        # Named volume, not a bind mount: podman seeds an empty volume from the
        # image, so /opt/couchdb/data ends up with the ownership the couchdb
        # user in the image expects instead of root-owned host directories.
        image = "docker.io/library/couchdb:3.3";
        environmentFiles = [ envFile ];
        volumes = [ "flohmarkt-couchdb-data:/opt/couchdb/data" ];
        pull = "missing";
      };

      flohmarkt = {
        image = cfg.image;
        cmd = [ "web" ];
        environmentFiles = [ envFile ];
        volumes = [ "${cfg.dataDir}:/var/lib/flohmarkt" ];
        ports = [ "${cfg.bindAddress}:${toString cfg.port}:8000" ];
        pull = "missing";
        dependsOn = [ "flohmarkt-couchdb" ];
      };
    };

    # CouchDB is not published on the host, so both the readiness probe and the
    # bootstrap have to run inside the podman network. The bootstrap is
    # idempotent (create-or-update of databases, users and design docs), which
    # is why the web container only waits for it instead of owning it.
    systemd.services.flohmarkt-initdb = {
      description = "Flohmarkt CouchDB bootstrap (databases, user, design docs)";
      after = [ "podman-flohmarkt-couchdb.service" ];
      requires = [ "podman-flohmarkt-couchdb.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.podman
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
        podman run --rm --network podman --env-file ${envFile} \
          -v ${cfg.dataDir}:/var/lib/flohmarkt ${cfg.image} initdb
      '';
    };

    systemd.services.podman-flohmarkt = {
      after = [ "flohmarkt-initdb.service" ];
      wants = [ "flohmarkt-initdb.service" ];
    };

    # Secrets stay host-local by design: only the two generated values ever
    # reach the env file, and neither passes through the nix store. The file is
    # re-rendered on every activation while the generated values persist, so the
    # containers keep the same credentials across switches.
    system.activationScripts.flohmarkt = lib.stringAfter [ "var" ] ''
      ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g root ${cfg.dataDir}
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
          'FLOHMARKT_DB_HOST=flohmarkt-couchdb' \
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
    '';
  };
}
