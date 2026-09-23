##
# Module: security/apparmor
# Purpose: AppArmor confinement for the network-facing daemons: the system
#   services (sshd, unbound, AdGuard Home, ntfy-sh, avahi) and the session ones
#   that parse network data as the login user (sing-box, transmission, aria2).
#   A profile attaches to the executable path, so it confines a user-session
#   service just as well as a system unit — and for those it is the only
#   boundary, since unit hardening (ProtectSystem=…) does not apply to them.
#   Every profile is generated from the daemon's own package closure
#   (pkgs.apparmorRulesFromClosure), so the file rules point at real Nix store
#   paths instead of the FHS paths upstream profiles assume — that is the
#   reason the shipped apparmor-profiles / roddhjav sets are NOT loaded here:
#   they attach to /usr/sbin/* and would never match a NixOS binary.
#   A profile only adds what the closure cannot know: state under /etc, /run
#   and /var, capabilities, network families. Local additions go through
#   security.apparmor.includes."local/<daemon>": every profile ends with
#   `include if exists <local/<daemon>>`. /etc is a read-only store symlink
#   farm on NixOS, so there is no writable /etc/apparmor.d/local to edit at
#   runtime — the include exists so a rule can be added from the config
#   without touching the profile body.
#   Both /etc and the home directory are symlink farms into the store and
#   AppArmor mediates the resolved path, so the module resolves them itself:
#   `etcFiles` for /etc (a trailing "/" expands to the whole subdirectory),
#   `homeFiles` for the nix-maid managed files under the main user's home.
#   Neither wildcards /nix/store, and both follow the generation on a switch.
#   (See docs/howto/apparmor.md for the iteration loop.)

# Key options: features.security.apparmor.{enable,sshd,unbound,adguardhome,ntfy,avahi,singbox,transmission,aria2}
#   Each daemon is independent: "disable" | "complain" | "enforce".
#   Defaults ship every profile in "complain" (denials are logged, nothing is
#   blocked). Flip one daemon to "enforce" only after its denials in
#   `journalctl -b --grep 'apparmor="DENIED"'` have been reviewed — see
#   docs/howto/apparmor.md.
#   apparmor.service loads /etc/apparmor.d (built from these policies) before
#   sysinit.target, so daemons start confined on the next boot; a `switch`
#   reloads/replaces profiles for the *next* exec of each binary.
# Dependencies: security.apparmor (this domain), pkgs.apparmor-profiles and
#   pkgs.roddhjav-apparmor-rules for the abstractions (base, nameservice,
#   ssl_certs) referenced from the include paths.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.security.apparmor;

  # The primary user: owns the session services below and the nix-maid file
  # tree their config files come from.
  mainUser = config.lib.neg.mainUser;

  # NixOS' /etc is a symlink farm into the store and AppArmor mediates the
  # *resolved* path, so a rule for /etc/<name> alone does not match the file
  # behind it. nixpkgs' own abstractions patch this the same way (see
  # nixos/modules/security/apparmor/includes.nix) — here it covers the
  # daemon-specific files that no shipped abstraction knows about.
  etcSource =
    name:
    let
      entry = config.environment.etc.${name} or null;
    in
    lib.optional (entry != null) entry.source;

  # A name ending in "/" expands to every environment.etc entry below it:
  # avahi publishes one file per service in /etc/avahi/services/, each a
  # directory entry pointing at its own store path, and each needs its own
  # resolved rule (a rule for the directory covers the listing, not the file).
  etcKeys =
    names:
    lib.concatMap (
      name:
      if lib.hasSuffix "/" name then
        lib.filter (k: lib.hasPrefix name k) (lib.attrNames config.environment.etc)
      else
        [ name ]
    ) names;

  # Files under the home directory reach a daemon through a symlink into the
  # store as well (nix-maid publishes them that way), and AppArmor mediates the
  # resolved path — the same trap as /etc. Resolve the store path out of
  # nix-maid's own file tree (users.users.<mainUser>.maid.file.home) instead of
  # wildcarding /nix/store; the path is regenerated on every switch, so the
  # rule follows the generation.
  maidStoreFile =
    relative:
    let
      files = config.users.users.${mainUser}.maid.file.home or { };
      entry = files.${relative} or null;
    in
    lib.optional (entry != null && entry.source != null) entry.source;

  # A few modules render their config into the store and pass the path on the
  # command line instead of publishing it in environment.etc (ntfy's
  # server.yml). Read it back from the rendered unit rather than wildcarding
  # the whole store.
  execStartPath =
    unit: flag:
    let
      match = builtins.match ".* ${flag} (/nix/store/[^ ]+).*" (
        toString config.systemd.services.${unit}.serviceConfig.ExecStart
      );
    in
    lib.optional (match != null) (builtins.head match);

  # What the closure rules cannot know, per daemon: /etc, /run and /var state,
  # capabilities, network families. The closure rules already grant read on
  # every store path of the package (libraries, share/, etc/), plus the binary
  # itself (added in mkProfile).
  daemons = {
    sshd = {
      package = config.services.openssh.package;
      exe = "sshd";
      etcFiles = [
        "ssh/sshd_config"
        "ssh/ssh_config"
        # pam_env reads the login environment (/etc/pam/environment).
        "pam/environment"
      ];
      extraIncludes = [
        "<abstractions/authentication>"
        "<abstractions/wutmp>"
        # pam_systemd talks to systemd-logind over the system bus and sshd
        # resolves users through the systemd NSS module.
        "<abstractions/dbus-strict>"
        "<abstractions/nss-systemd>"
      ];
      rules = ''
        # /etc/ssh holds the real host keys (generated at activation) plus the
        # sshd_config symlink whose store target is added via etcFiles; the PAM
        # stack, /etc/shadow and the name service files come from
        # <abstractions/authentication> and <abstractions/nameservice>.
        /etc/ssh/** r,
        /run/sshd/ rw,
        /run/sshd/** rw,
        # Only for configs that keep the upstream PidFile (the openssh module
        # here moves it into /run/sshd).
        /run/sshd.pid rw,
        # glibc dlopens the systemd NSS module for users/groups coming from
        # systemd (nixpkgs' nameservice abstraction covers pkgs.nss only).
        ${config.systemd.package}/lib/libnss_systemd.so.2 mr,
        # AuthorizedKeysFile %h/.ssh/authorized_keys for login users, plus the
        # per-user drop-in dir the NixOS module uses for authorized_keys.d.
        /root/.ssh/** r,
        /home/*/.ssh/** r,
        # sshd reads the controlling terminal and adjusts its own OOM score.
        /dev/tty r,
        /proc/*/gid_map r,
        /proc/*/loginuid rw,
        /proc/*/oom_adj rw,
        /proc/*/oom_score_adj rw,
        /proc/*/uid_map r,
        /run/utmp rw,
        /var/log/wtmp rw,
        /var/log/btmp rw,
        # pam_unix authenticates through the setuid helper; it runs inside
        # this profile (ix) and reads /etc/shadow, granted above.
        # NixOS mounts security.wrappers in a randomised directory under
        # /run/wrappers (wrappers.<hash>/), so match the directory instead of
        # the stable /run/wrappers/bin symlink.
        /run/wrappers/wrappers.*/unix_chkpwd ixr,
        /nix/store/*-linux-pam-*/bin/unix_chkpwd ixr,
        /run/wrappers/bin/unix_chkpwd ixr,
        /run/current-system/sw/bin/unix_chkpwd ixr,
        # Sessions must NOT inherit this profile. After the fork sshd execs the
        # user's login shell, and an interactive session legitimately runs
        # arbitrary code — confining it here would break every login. The
        # daemon and its privilege-separated child stay confined; the session
        # process is started unconfined (Ux), which is the documented limit of
        # this profile.
        /bin/sh Ux,
        /bin/bash Ux,
        /run/current-system/sw/bin/bash Ux,
        /run/current-system/sw/bin/zsh Ux,
        /run/current-system/sw/bin/fish Ux,
        /nix/store/*/bin/bash Ux,
        /nix/store/*/bin/zsh Ux,
        /nix/store/*/bin/fish Ux,
        capability audit_write,
        capability chown,
        capability dac_override,
        capability dac_read_search,
        capability fowner,
        capability kill,
        capability net_bind_service,
        capability setgid,
        capability setuid,
        capability sys_chroot,
        capability sys_resource,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    unbound = {
      package = config.services.unbound.package;
      exe = "unbound";
      etcFiles = [ "unbound/unbound.conf" ];
      rules = ''
        # /etc/unbound/unbound.conf is a symlink into the store (etcFiles
        # adds its target); the trust anchor (root.key) and the remote-control
        # certs are written under the StateDirectory, the pid under
        # RuntimeDirectory.
        /etc/unbound/ r,
        /var/lib/unbound/** rwlk,
        /run/unbound/ rw,
        /run/unbound/** rw,
        /run/systemd/notify w,
        # The unbound unit gets CAP_NET_BIND_SERVICE + CAP_NET_RAW ambient.
        capability net_bind_service,
        capability net_raw,
        capability setgid,
        capability setuid,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    adguardhome = {
      package = config.services.adguardhome.package;
      exe = "AdGuardHome";
      etcFiles = [
        "lsb-release"
        "os-release"
      ];
      rules = ''
        # Work dir: AdGuardHome.yaml, data/, query log, filters and stats.
        # `lk` is needed: sessions.db is opened with flock.
        /var/lib/AdGuardHome/** rwlk,
        /run/AdGuardHome/ rw,
        /run/AdGuardHome/** rw,
        # It lists /etc and reads the ARP table for client discovery (the
        # `arp`/`ip` fallbacks in that code path stay denied — the daemon logs
        # an error and keeps serving).
        /etc/ r,
        /proc/*/cgroup r,
        /proc/*/mountinfo r,
        /proc/*/net/arp r,
        # The Go runtime reads socket defaults and its own cgroup CPU quota
        # (GOMAXPROCS) at startup.
        /proc/sys/net/core/ r,
        /proc/sys/net/core/somaxconn r,
        /sys/fs/cgroup/system.slice/adguardhome.service/cpu.max r,
        # The admin config is written through a temp file next to the target;
        # AdGuard picks /tmp. The unit sets PrivateTmp=true, so this is the
        # service's own tmp namespace.
        /tmp/ rw,
        /tmp/** rwk,
        /run/systemd/notify w,
        /etc/hosts r,
        /etc/resolv.conf r,
        # DNS on 127.0.0.1:53 and the admin UI on 127.0.0.1:3000.
        capability net_bind_service,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    ntfy = {
      package = config.services.ntfy-sh.package;
      exe = "ntfy";
      # ntfy shells out to `uname` (coreutils) and reads os-release.
      extraPackages = [ pkgs.coreutils ];
      etcFiles = [ "os-release" ];
      # server.yml is rendered into the store and passed as `-c <path>`.
      extraPaths = execStartPath "ntfy-sh" "-c";
      rules = ''
        # DynamicUser: /var/lib/ntfy-sh is a bind mount of
        # /var/lib/private/ntfy-sh (both spellings appear to the kernel
        # depending on the mount), /run/ntfy-sh holds the pid file. The cache
        # database is flock()ed.
        /var/lib/ntfy-sh/ r,
        /var/lib/ntfy-sh/** rwlk,
        /var/lib/private/ntfy-sh/ r,
        /var/lib/private/ntfy-sh/** rwlk,
        /run/ntfy-sh/ rw,
        /run/ntfy-sh/** rwlk,
        /proc/*/cgroup r,
        /proc/*/mountinfo r,
        # The Go runtime reads its own cgroup CPU quota (GOMAXPROCS) at startup.
        /proc/sys/net/core/ r,
        /proc/sys/net/core/somaxconn r,
        /sys/fs/cgroup/system.slice/ntfy-sh.service/cpu.max r,
        /run/systemd/notify w,
        # listen-http = ":2586" needs the ambient CAP_NET_BIND_SERVICE.
        capability net_bind_service,
        network inet stream,
        network inet dgram,
      '';
    };

    # ---- session services (user@1000) --------------------------------------
    # Started by the login session rather than by systemd --system, but a
    # profile attaches to the executable path, so these are confined just the
    # same. For them the profile is the only boundary a unit has no
    # ProtectSystem=… — and they all parse data that arrives over the network.

    singbox = {
      package = pkgs.sing-box;
      exe = "sing-box";
      rules = ''
        # sing-box-proxy (user unit) reads -c ~/.config/sing-box-trojan/
        # config.json; the system unit sing-box-tun runs the same binary with
        # /run/sing-box-tun/config.json and opens the TUN device. One profile
        # covers both.
        /home/*/.config/sing-box*/ r,
        /home/*/.config/sing-box*/** r,
        /run/sing-box-tun/ r,
        /run/sing-box-tun/** r,
        /dev/net/tun rw,
        /proc/*/cgroup r,
        /proc/*/mountinfo r,
        /proc/sys/net/core/ r,
        /proc/sys/net/core/somaxconn r,
        # The Go runtime reads its own cgroup CPU quota (GOMAXPROCS): the
        # session slice for the user proxy, the system slice for the TUN unit.
        /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/sing-box-proxy.service/cpu.max r,
        /sys/fs/cgroup/system.slice/sing-box-tun.service/cpu.max r,
        # The TUN instance creates routes and the interface (its unit holds
        # ambient CAP_NET_ADMIN); the SOCKS inbound with password auth binds
        # an unprivileged port.
        capability net_admin,
        capability net_raw,
        network netlink raw,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    transmission = {
      package = pkgs.transmission_4;
      exe = "transmission-daemon";
      # nix-maid owns these files: the daemon opens the setting/state files and
      # the XDG user-dirs file through the store symlinks, so the resolved
      # paths have to be in the profile (a rule for ~/.config/... is not
      # enough). Without this the daemon would fall back to default settings —
      # other dirs, ports and RPC port — which is why it matters before enforce.
      homeFiles = [
        ".config/transmission-daemon/settings.json"
        ".config/transmission-daemon/bandwidth-groups.json"
        ".config/user-dirs.dirs"
      ];
      rules = ''
        # -g ~/.config/transmission-daemon: settings.json (rewritten by the
        # daemon), torrents/, resume/, stats.json. `lk` covers the flock on
        # settings.json and the resume files.
        /home/*/.config/transmission-daemon/ rw,
        /home/*/.config/transmission-daemon/** rwlk,
        # download-dir = ~/torrent/data, watch-dir = ~/dw (a .torrent is
        # deleted from there once picked up); the web UI/transmission-remote
        # also add and remove data files here.
        /home/*/torrent/ rw,
        /home/*/torrent/** rwlk,
        /home/*/dw/ rw,
        /home/*/dw/** rwlk,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    aria2 = {
      package = pkgs.aria2;
      exe = "aria2c";
      # Both files are nix-maid store symlinks (the session file is the seed
      # one; aria2 rewrites it in place, which fails on a read-only store path
      # and is not something a profile can fix).
      homeFiles = [
        ".config/aria2/aria2.conf"
        ".local/share/aria2/session"
      ];
      rules = ''
        # --conf-path ~/.config/aria2/aria2.conf, session file under
        # ~/.local/share/aria2 (read at start, rewritten every
        # save-session-interval).
        /home/*/.config/aria2/ r,
        /home/*/.config/aria2/** r,
        /home/*/.local/share/aria2/ rw,
        /home/*/.local/share/aria2/** rwlk,
        # dir = ~/dw/aria. Deliberately not all of /home: an RPC caller may
        # pass its own dir=, so enforcing this needs the reviewed denials.
        /home/*/dw/ rw,
        /home/*/dw/** rwlk,
        # aria2 looks for ~/.netrc for HTTP credentials.
        /home/*/.netrc r,
        # RPC on 127.0.0.1:6800, download sockets are ephemeral.
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };

    avahi = {
      package = pkgs.avahi;
      exe = "avahi-daemon";
      # The unit execs .../avahi-0.8/sbin/avahi-daemon, but AppArmor attaches to
      # the *resolved* path (sbin/ is a symlink to bin/), which is also what the
      # default /bin/ in mkProfile builds.
      # The unit passes a store-rendered config on the command line.
      extraPaths = execStartPath "avahi-daemon" "-f";
      # /etc/avahi/services/smb.service and friends: one store path each.
      etcFiles = [ "avahi/services/" ];
      rules = ''
        # avahi-daemon drops to the avahi user and chroots into its runtime
        # dir; the D-Bus name is what actually starts it.
        /etc/avahi/ r,
        # The store targets of the service files come from etcFiles above; the
        # directory itself still needs a rule to be listed.
        /etc/avahi/services/ r,
        /run/avahi-daemon/ rw,
        # /run/avahi-daemon/pid is flock()ed, hence the `lk`.
        /run/avahi-daemon/** rwlk,
        /run/dbus/system_bus_socket rw,
        /run/systemd/notify w,
        /proc/*/mountinfo r,
        # dlopen'ed, so neither library is in the package closure: avahi links
        # against systemd's sd_notify and resolves mDNS names through the
        # nss-mdns module (services.avahi.nssmdns4/6 in modules/servers/avahi).
        ${pkgs.systemd}/lib/libsystemd.so.* mr,
        ${pkgs.nssmdns}/lib/libnss_mdns.so.2 mr,
        capability dac_override,
        capability net_bind_service,
        capability net_raw,
        capability setgid,
        capability setuid,
        capability sys_chroot,
        # mDNS on 5353/udp; netlink to watch interfaces (the route monitor
        # socket is dgram, the address dump one is raw).
        network netlink dgram,
        network netlink raw,
        network inet stream,
        network inet dgram,
        network inet6 stream,
        network inet6 dgram,
      '';
    };
  };

  # Indent the rule block by two spaces and keep a trailing newline so the
  # rendered /etc/apparmor.d/<name> file stays readable (diffable against
  # aa-logprof output).
  indent = text: lib.concatMapStrings (line: "  ${line}\n") (lib.splitString "\n" text);

  mkProfile =
    name: daemon:
    let
      helperPackages = daemon.extraPackages or [ ];
      header = [
        "abi <abi/4.0>,"
        "include <tunables/global>"
        ""
        "# Generated by modules/security/apparmor.nix — do not edit in place:"
        "# local rules belong in security.apparmor.includes.\"local/${name}\"."
        "profile ${daemon.package}/bin/${daemon.exe} flags=(attach_disconnected) {"
        "  include <abstractions/base>"
        "  include <abstractions/nameservice>"
        "  include <abstractions/ssl_certs>"
      ];
      includes = map (i: "  include ${i}") (daemon.extraIncludes or [ ]);
      # /etc entries and generated store files the daemon reads.
      storePaths = map (p: "  ${p} r,") (
        (lib.concatMap etcSource (etcKeys (daemon.etcFiles or [ ])))
        ++ (daemon.extraPaths or [ ])
        ++ (lib.concatMap maidStoreFile (daemon.homeFiles or [ ]))
      );
      # Helper binaries the daemon shells out to: their closure must be
      # readable and the binaries executable inside this profile.
      helperClosure =
        lib.optional (helperPackages != [ ])
          ''include "${pkgs.apparmorRulesFromClosure { name = "neg-${name}-extra"; } helperPackages}"'';
      helperExec = map (p: "  ${p}/bin/* ixr,") helperPackages;
      body = [
        "  # The attached binary itself (the attachment only grants the profile"
        "  # transition, not the read)."
        "  ${daemon.package}/bin/${daemon.exe} mr,"
        "  include \"${pkgs.apparmorRulesFromClosure { name = "neg-${name}"; } [ daemon.package ]}\""
      ];
      ruleLines = lib.splitString "\n" (lib.removeSuffix "\n" (indent (lib.trim daemon.rules)));
    in
    lib.concatStringsSep "\n" (
      header
      ++ includes
      ++ storePaths
      ++ helperClosure
      ++ helperExec
      ++ body
      ++ ruleLines
      ++ [
        "  include if exists <local/${name}>"
        "}"
      ]
    )
    + "\n";

  enabledDaemons = lib.filterAttrs (name: _: cfg.${name} != "disable") daemons;
in
{
  config = lib.mkIf cfg.enable {
    security.apparmor.policies = lib.mapAttrs' (name: daemon: {
      inherit name;
      value = {
        state = cfg.${name};
        profile = mkProfile name daemon;
      };
    }) enabledDaemons;
  };
}
