{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;

  # dsh-desktop: Linux desktop control (computer-use-linux + grim). Server
  # plugin, host plane — same pattern as dsh-osm. The package is a plain
  # directory in the profile node_modules; the CUL binary is a prebuilt
  # GitHub release (not in nixpkgs), fetched once into ~/.local/bin and
  # patchelf'ed for NixOS (dynamic loader). Files are written only when
  # missing, so local tweaks survive; to re-apply a changed copy from this
  # module, delete ~/.dsh/profiles/web/node_modules/dsh-desktop and restart dsh.
  pkg = ./dsh-desktop;

  culVersion = "0.4.9";
  culUrl = "https://github.com/agent-sh/computer-use-linux/releases/download/v${culVersion}/computer-use-linux-x86_64-unknown-linux-gnu";
  culSha256 = "6432e86ee6480f31f508f22dbe860d6987859997ee476ca36324a38e2eb4df48";
  ldSo = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
  culRpath = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib";

  ensure = pkgs.writeShellScript "dsh-desktop-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-desktop"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        # CUL prebuilt binary: fetch once, verify sha256, patchelf for NixOS
        BIN="${homeDir}/.local/bin/computer-use-linux"
        if [ ! -x "$BIN" ]; then
          mkdir -p "${homeDir}/.local/bin"
          TMP="$P/.cul-bin"
          curl -sL --max-time 180 --proxy socks5h://127.0.0.1:10808 -o "$TMP" "${culUrl}" || curl -sL --max-time 180 -o "$TMP" "${culUrl}"
          echo "${culSha256}  $TMP" | sha256sum -c -
          ${pkgs.patchelf}/bin/patchelf --set-interpreter "${ldSo}" --set-rpath "${culRpath}" "$TMP"
          install -m755 "$TMP" "$BIN"
          rm -f "$TMP"
          echo "computer-use-linux ${culVersion} installed to $BIN"
        fi
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-desktop' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-desktop - Linux desktop control (computer-use-linux + grim)
    # (module: dsh-desktop.nix).
    - insert:
        - id: desktop
          name: dsh-desktop
    YAML
          changed=1
        fi
        if [ "$changed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          ${pkgs.neg.dsh-restart}/bin/dsh-restart
        fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshDesktop = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-desktop = {
    enable = true;
    description = "dsh-desktop — ensure desktop control tool in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
