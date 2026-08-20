inputs: final: finalPrev:
let
  importOv = path: import path inputs final finalPrev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
  fixTinycc = importOv ./overlays/fix-tinycc.nix;
  aurPorted = import ./overlays/aur-ported.nix final finalPrev;

  # WARNING: disableChecks MUST be last in the merge chain (//) below.
  # It calls overrideAttrs which resets any prior overrides on the same package.
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fixTinycc // aurPorted // disableChecks)
// {
  # Carla: vendored source tarball (GitHub fetch unreliable behind the proxy).
  # Vendored archives live in files/sources/ and are TRACKED in git (the
  # relative-path pattern): flake builds are pure, so absolute store paths or
  # builtins.storePath are forbidden — only relative references to tracked
  # files work. Keep the tarball in git; do not switch to store paths.
  carla = finalPrev.carla.overrideAttrs (_: {
    src = ./../files/sources/carla-2.5.10.tar.gz;
  });

  # a2jmidid: nixpkgs fetches from gitea.ladish.org (unresolvable from the
  # build sandbox); vendor the GitHub mirror tarball (same tag 12).
  a2jmidid = finalPrev.a2jmidid.overrideAttrs (old: {
    src = ./../files/sources/a2jmidid-12.tar.gz;
  });

  # dpkg: nixpkgs fetches the source from git.launchpad.net (unreachable from
  # this region); vendor the official Debian release tarball (has .dist-version,
  # which get-version needs) instead. dpkg is needed by ocenaudio and
  # cloudflare-warp to unpack .debs.
  dpkg = finalPrev.dpkg.overrideAttrs (_: {
    src = ./../files/sources/dpkg-1.23.7.tar.xz;
  });

  # ouch 0.8.1: "ignore invalid unix permissions and setuid bits from zip"
  # (upstream PR #1007). The pinned nixpkgs-weekly still ships 0.8.0, which
  # applies garbage Unix modes stored in bandcamp pre-order zips (e.g. 0o4032)
  # literally — extracted files end up unreadable by the owner. ouch is the
  # backend of the `se`/`pk` aliae aliases (lib/aliae.nix). MANUALLY PINNED:
  # built via rustPlatform.buildRustPackage because overrideAttrs on the
  # packaged 0.8.0 keeps the old cargoDeps/vendor-staging hash (new rust
  # platform flow), which makes the fixed-output fetch fail.
  ouch = finalPrev.rustPlatform.buildRustPackage rec {
    pname = "ouch";
    version = "0.8.1";
    src = finalPrev.fetchFromGitHub {
      owner = "ouch-org";
      repo = "ouch";
      rev = version;
      hash = "sha256-fxBalMi5xdLNBnd5VIdAYDIjbSBrOPrmpKlKW1DmbxQ=";
    };
    cargoHash = "sha256-kYef8Xsi1gO0V2yXHiTkPi2rFjECw3jjhADSMhhu5zg=";
    # 0.8.1 sanitizes the archive mode but still creates files with the
    # (garbage) mode: for bandcamp zips (mode 0o4032, no S_IFMT) that yields
    # 0o032 -> umask -> 0o010 and extraction fails with EACCES. Backport the
    # upstream main fix (valid_unix_permissions): fall back to 0o644 when the
    # zip mode carries no Unix file-type bits.
    patches = [ ./overlays/ouch-valid-unix-perms.patch ];
    nativeBuildInputs = [
      finalPrev.cmake
      finalPrev.installShellFiles
      finalPrev.pkg-config
      finalPrev.rustPlatform.bindgenHook
    ];
    nativeCheckInputs = [ finalPrev.git ];
    buildInputs = [
      finalPrev.bzip2
      finalPrev.bzip3
      finalPrev.xz
      finalPrev.zlib
      finalPrev.zstd
    ];
    buildNoDefaultFeatures = true;
    buildFeatures = [
      "use_zlib"
      "use_zstd_thin"
      "bzip3"
      "zstd/pkg-config"
    ];
    postInstall = ''
      installManPage artifacts/*.1
      installShellCompletion artifacts/ouch.{bash,fish} --zsh artifacts/_ouch --nushell artifacts/ouch.nu
    '';
    env.OUCH_ARTIFACTS_FOLDER = "artifacts";
    meta = {
      description = "Command-line utility for easily compressing and decompressing files and directories";
      homepage = "https://github.com/ouch-org/ouch";
      changelog = "https://github.com/ouch-org/ouch/blob/${version}/CHANGELOG.md";
      license = finalPrev.lib.licenses.mit;
      maintainers = with finalPrev.lib.maintainers; [
        psibi
        krovuxdev
        philocalyst
      ];
      platforms = finalPrev.lib.platforms.all;
      mainProgram = "ouch";
    };
  };

  # pffft/fuzzysearchdatabase: bitbucket.org is RKN-blocked here
  # (DNS-poisoned, sandboxed fetches hang). The attribute overrides below
  # cover direct consumers of the pkgs.pffft / pkgs.fuzzysearchdatabase
  # attributes; vcv-rack's own dep/ fetches are covered by the
  # fetchFromBitbucket override further down (same vendored tarballs).
  # (Tarballs are tracked in files/sources/ and referenced by relative path —
  # see the carla note above.)
  pffft = finalPrev.pffft.overrideAttrs (_: {
    src = ./../files/sources/pffft-74d7261.tar.gz;
  });

  fuzzysearchdatabase = finalPrev.fuzzysearchdatabase.overrideAttrs (_: {
    src = ./../files/sources/fuzzysearchdatabase-23122d1.tar.gz;
  });

  # vcv-rack vendors its dep/ libraries itself: its package.nix calls
  # fetchFromBitbucket for fuzzysearchdatabase and pffft, so attribute
  # overrides never reach it. Intercept fetchFromBitbucket for those two
  # repos and serve the local tarballs instead (unpacked content verified
  # byte-identical to the nixpkgs fetchzip hashes). Everything else falls
  # through to the original.
  fetchFromBitbucket =
    args:
    let
      vendored = {
        "jpommier/pffft" = ./../files/sources/pffft-74d7261.tar.gz;
        "j_norberg/fuzzysearchdatabase" = ./../files/sources/fuzzysearchdatabase-23122d1.tar.gz;
      };
      key = "${args.owner or ""}/${args.repo or ""}";
    in
    if builtins.hasAttr key vendored then
      finalPrev.stdenv.mkDerivation {
        pname = "${args.repo or "vendored"}-vendored";
        version = args.rev or args.tag or "local";
        src = vendored.${key};
        phases = [
          "unpackPhase"
          "installPhase"
        ];
        installPhase = ''
          mkdir -p $out
          cp -r ./. $out/
        '';
      }
    else
      finalPrev.fetchFromBitbucket args;

  # vcv-rack's Makefile declares no dependency between the plugin sub-make
  # and libRack.so, but nixpkgs passes "all plugins" to one parallel make —
  # the plugin link can read libRack.so mid-write and fail with
  # "file format not recognized" (flaky). Build `all` first, then plugins in
  # postBuild (the same split nixpkgs already uses for the Darwin dist target).
  vcv-rack = finalPrev.vcv-rack.overrideAttrs (old: {
    makeFlags = builtins.filter (flag: flag != "plugins") (old.makeFlags or [ ]);
    postBuild =
      (old.postBuild or "")
      + finalPrev.lib.optionalString (!finalPrev.stdenv.hostPlatform.isDarwin) ''
        make plugins
      '';
  });

  # GHCi with TidalCycles library preloaded — used by tidal.nvim
  tidal-ghci = final.writeShellScriptBin "tidal-ghci" ''
    exec ${final.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@" # TidalCycles GHCi wrapper
  '';

  # Merge all pkgs.neg sub-attributes from individual overlays
  neg =
    (functions.neg or { })
    // (tools.neg or { })
    // (media.neg or { })
    // (dev.neg or { })
    // (gui.neg or { })
    // {
      game = final.callPackage ./game { };
      joern = final.callPackage ./joern { }; # Open-source code analysis platform
      superdirt = final.callPackage ./superdirt { }; # SuperDirt SC quark for TidalCycles audio engine
      dirt-samples = final.callPackage ./dirt-samples { }; # audio sample library for SuperDirt
      vowel = final.callPackage ./vowel { }; # Vowel SC quark (formant tables) used by SuperDirt
      dsh = final.callPackage ./dsh { }; # DeepSeek Harness agent CLI (dsh)
      # dsh web @deepseek-ai tree with hardcoded Chinese UI copy -> English
      # (profile's @deepseek-ai symlink points here, see dsh-market.nix)
      dsh-web-en = final.callPackage ./dsh/web-ui-en { dsh = final.neg.dsh; };
      # dsh-restart: reliable restart of the dsh web user service. Plain
      # 'systemctl --user restart' dies with "Failed to kill control group:
      # Operation not permitted" when root processes (e.g. 'sudo nixos-rebuild'
      # typed into a web terminal) sit in the service cgroup — the old node
      # never frees port 3080, the start fails and the unit is left dead. This
      # stops the unit, waits it out, kills straggler web processes and only
      # then starts it again.
      dsh-restart = final.writeShellScript "dsh-restart" ''
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        systemctl --user stop dsh.service 2>/dev/null || true
        i=0
        while [ "$i" -lt 30 ]; do
          s="$(systemctl --user is-active dsh.service 2>/dev/null || true)"
          [ "$s" = "inactive" ] || [ "$s" = "failed" ] && break
          sleep 1
          i=$((i + 1))
        done
        pkill -f '/lib/bin\.js web' 2>/dev/null || true
        sleep 1
        systemctl --user start dsh.service 2>/dev/null || true
      '';
      zest = final.callPackage ./zest { }; # CLI for ZestBay plugin management (LV2 add/rm/list)
      carlactl = final.callPackage ./carlactl { }; # console VST router via headless Carla (list/run/route)
      wineapps = final.callPackage ./wineapps { }; # declarative Wine app manager (list/install/uninstall/run)
    };

  # tmd-top: real-time per-IP network traffic monitor (TUI) — pinned textual 1.0.0
  # stack on python312, see packages/tmd-top/default.nix
  tmd-top = final.callPackage ./tmd-top { };

  # tewi: TUI client for Transmission/qBittorrent/Deluge daemons
  # (python app, deps from nixpkgs + local geoip2fast, see packages/tewi/default.nix)
  tewi = final.callPackage ./tewi { };

  # Code200x Unicode font family by James Kass — Code2000 (BMP), Code2001
  # (Plane 1 ancient scripts), Code2002 (Plane 2 rare CJK), Code20X3 (Plane 3 CJK Ext G/H)
  ttf-code2000 = final.callPackage ./ttf-code2000 { };
  ttf-code2001 = final.callPackage ./ttf-code2001 { };
  ttf-code2002 = final.callPackage ./ttf-code2002 { };
  ttf-code20x3 = final.callPackage ./ttf-code20x3 { };

  # Python with LTO optimizations
  python3-lto = finalPrev.python3.override {
    packageOverrides = _pythonSelf: _pythonSuper: {
      enableOptimizations = true;
      enableLTO = true;
      reproducibleBuild = false;
    };
  };

  # Fix keyutils patch download failing (upstream lore.kernel.org 403)
  keyutils = finalPrev.keyutils.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      |> builtins.map (
        p:
        if builtins.isAttrs p && (p.name or "") == "raw" then
          ./../files/patches/keyutils-fix-format-specifier.patch
        else
          p
      );
  });

  # Fix /sbin/ldconfig symlink in FHS envs (Steam pressure-vessel nested container fix).
  # Symlinking /sbin/ldconfig -> /bin/ldconfig creates a resolution loop when
  # pressure-vessel tries to set up a nested bwrap container for Proton.
  # Copy the binary instead, as SteamRT3 expects.
  buildFHSEnv =
    args:
    finalPrev.buildFHSEnv (
      args
      // {
        extraBuildCommands = (args.extraBuildCommands or "") + ''
          if [ -L $out/usr/sbin/ldconfig ] && [ -f $out/usr/bin/ldconfig ]; then
            cp -f $out/usr/bin/ldconfig $out/usr/sbin/ldconfig
          fi
        '';
      }
    );

  # Flatpak: drop gtk3 from buildInputs — upstream meson.build doesn't require it.
  # Note: postInstall still wraps gtk-icon-cache.trigger with gtk3; the reference
  # may persist in the closure but this is negligible (~10MB) vs what was removed.
  flatpak = finalPrev.flatpak.overrideAttrs (old: {
    buildInputs = builtins.filter (pkg: (pkg.pname or "") != "gtk3") (old.buildInputs or [ ]);
  });

  # Ollama ROCm: build the ROCm stack for only the local GPU architecture
  # (gfx1201 — Navi 48 / RX 9070 XT) instead of all 10 default targets.
  # hipblaslt's Tensile codegen generates ~323k assembly kernels per arch;
  # scoping to one arch cuts the ROCm build from many hours to a fraction.
  ollama-rocm = finalPrev.ollama-rocm.override {
    rocmPackages = finalPrev.rocmPackages.gfx1201;
  };

  # untangle 1.2.1 (debugpy dep for the nvim python host env): the upstream
  # GitHub tag was re-pushed, so the archive no longer matches the hash pinned
  # in nixpkgs 26.05 (fixed-output fetch fails with a hash mismatch every
  # time). Vendor the current official archive instead (version still 1.2.1;
  # relative-path pattern — see the carla note above).
  python3 = finalPrev.python3.override {
    packageOverrides = _pfinal: pprev: {
      untangle = pprev.untangle.overrideAttrs (_: {
        src = ./../files/sources/untangle-1.2.1.tar.gz;
      });
    };
  };

}
