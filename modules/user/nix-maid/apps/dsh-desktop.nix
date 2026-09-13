{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

  # dsh-desktop: Linux desktop control. computer-use-linux (used by the TUI's
  # dsh-desktop plugin through the `desktop` tool) is a prebuilt GitHub release,
  # not in nixpkgs — fetched once into ~/.local/bin and patchelf'ed for NixOS
  # (dynamic loader). The web-profile copy was removed in 2026-09.

  culVersion = "0.4.9";
  culUrl = "https://github.com/agent-sh/computer-use-linux/releases/download/v${culVersion}/computer-use-linux-x86_64-unknown-linux-gnu";
  culSha256 = "6432e86ee6480f31f508f22dbe860d6987859997ee476ca36324a38e2eb4df48";
  ldSo = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
  culRpath = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib";

  installCul = pkgs.writeShellScript "dsh-desktop-cul" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    # CUL prebuilt binary: fetch once, verify sha256, patchelf for NixOS.
    BIN="${homeDir}/.local/bin/computer-use-linux"
    if [ ! -x "$BIN" ]; then
      mkdir -p "${homeDir}/.local/bin"
      TMP="$(mktemp)"
      curl -sL --max-time 180 --proxy socks5h://127.0.0.1:10808 -o "$TMP" "${culUrl}" || curl -sL --max-time 180 -o "$TMP" "${culUrl}"
      echo "${culSha256}  $TMP" | sha256sum -c -
      ${pkgs.patchelf}/bin/patchelf --set-interpreter "${ldSo}" --set-rpath "${culRpath}" "$TMP"
      install -m755 "$TMP" "$BIN"
      rm -f "$TMP"
      echo "computer-use-linux ${culVersion} installed to $BIN"
    fi
  '';
in
{
  # AT-SPI accessibility bus (org.a11y.Bus): required for semantic selectors
  # in dsh-desktop (CUL list_apps / get_app_state / click-by-name). The bus is
  # D-Bus activated on demand — no resident daemon, near-zero idle cost.
  # at-spi2-core ships the activation unit + the .service file; the
  # consolidated dbus dir (modules/user/dbus.nix) picks up dbus.packages.
  services.dbus.packages = [ pkgs.at-spi2-core ];
  # user unit for dbus activation of org.a11y.Bus (SystemdService in the
  # .service file points here); at-spi2-core ships the unit file, we just
  # declare it so dbus-broker can start it on demand.
  systemd.user.services."at-spi-dbus-bus" = {
    enable = true;
    description = "Accessibility services bus";
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "dbus";
      BusName = "org.a11y.Bus";
      # --a11y=1 sets org.a11y.Status.IsEnabled=true on the bus at
      # startup: without it GTK/Qt apps do not export accessibility trees
      # and CUL list_apps returns an empty accessible_apps list.
      ExecStart = "${pkgs.at-spi2-core}/libexec/at-spi-bus-launcher --a11y=1";
      Slice = "session.slice";
      TimeoutStopSec = 5;
    };
  };

  # Keep the CUL binary present on every rebuild and login: it is a plain file
  # in ~/.local/bin, not a profile package, so nothing else restores it.
  system.activationScripts.dshDesktop = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = installCul;
  };

  systemd.user.services.dsh-desktop-cul = systemdUser.mkUserOneshot {
    description = "computer-use-linux — keep the desktop-control binary in ~/.local/bin";
    script = installCul;
    after = [ "network.target" ];
  };
}
