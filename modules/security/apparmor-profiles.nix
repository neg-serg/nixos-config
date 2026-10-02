##
# Data: security/apparmor profiles
# Purpose: per-daemon profile bodies consumed by modules/security/apparmor.nix.
#   Each entry names the executable, the package whose closure supplies the
#   file rules, the daemon-specific /etc and home paths, any extra abstractions
#   and the literal AppArmor rules. The consumer keeps the options, the
#   complain/enforce gating and the mkProfile renderer; this file is data only.
{
  config,
  pkgs,
  execStartPath,
}:
{
  # What the closure rules cannot know, per daemon: /etc, /run and /var state,
  # capabilities, network families. The closure rules already grant read on
  # every store path of the package (libraries, share/, etc/), plus the binary
  # itself (added in mkProfile).
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
      # The RPC session id lives in a file it creates under /tmp (only when
      # RPC is actually used — this is what an enforced run found that the
      # host's complain log did not show yet).
      /tmp/ r,
      /tmp/tr_session_id_* rwk,
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
      # avahi asks systemd who this host is (a plain file on NixOS, not a
      # store symlink) — the enforced VM run hit this, the host's complain log
      # had not yet, because the read is conditional.
      /etc/machine-id r,
      /run/avahi-daemon/ rw,
      # /run/avahi-daemon/pid is flock()ed, hence the `lk`.
      /run/avahi-daemon/** rwlk,
      /run/dbus/system_bus_socket rw,
      /run/systemd/notify w,
      /proc/*/mountinfo r,
      # dlopen'ed, so neither library is in the package closure: avahi links
      # against systemd's sd_notify and resolves mDNS names through the
      # nss-mdns module (services.avahi.nssmdns4/6 in modules/servers/avahi),
      # while glibc's NSS path pulls in systemd's own nss module the same way
      # sshd does.
      ${pkgs.systemd}/lib/libsystemd.so.* mr,
      ${pkgs.nssmdns}/lib/libnss_mdns.so.2 mr,
      ${config.systemd.package}/lib/libnss_systemd.so.2 mr,
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
}
