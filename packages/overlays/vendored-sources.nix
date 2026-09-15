# Vendored-source overrides: the upstream fetch is unreachable from this
# host/region (RKN-blocked host, forced 403, re-pushed tag, unresolvable
# mirror), so the tarball/patch is committed under files/sources/ (or
# files/patches/) and referenced by a *relative path literal*
# (`./../../files/sources/...`). Being a path, Nix copies it into the store and
# tracks it as a closure dependency — the same behavior as a remote fetch.
# Exception: files >100 MB (the licensed Renoise installers) cannot be
# committed (GitHub rejects them), and relocating them inside the tree does not
# work either (the flake source is tracked-files-only; absolute paths are
# forbidden in pure evaluation). They live outside the repo and arrive as the
# `renoise-src` path input (flake.nix); see the renoise block below.
# Other overlays refer to this as "the vendored-tarball note in
# overlays/vendored-sources.nix".
inputs: final: finalPrev: {
  # a2jmidid: nixpkgs fetches from gitea.ladish.org (unresolvable from the
  # build sandbox); vendor the GitHub mirror tarball (same tag 12) + the
  # siginfo submodule (needed by sigsegv.c/a2jmidid.c).
  a2jmidid = finalPrev.a2jmidid.overrideAttrs (old: {
    src = ./../../files/sources/a2jmidid-12.tar.gz;
    postUnpack = (old.postUnpack or "") + ''
      mkdir -p "$sourceRoot/siginfo"
      tar xzf ${./../../files/sources/a2jmidid-siginfo.tar.gz} -C "$sourceRoot/siginfo" --strip-components=1
    '';
  });

  # dpkg: nixpkgs fetches the source from git.launchpad.net (unreachable from
  # this region); vendor the official Debian release tarball (has .dist-version,
  # which get-version needs) instead. dpkg is needed by ocenaudio and
  # cloudflare-warp to unpack .debs.
  dpkg = finalPrev.dpkg.overrideAttrs (_: {
    src = ./../../files/sources/dpkg-1.23.7.tar.xz;
  });

  # renoise: full licensed release tarball (user's own Renoise 3.5.4 build,
  # backstage.renoise.com download — not the public demo). Too large to commit,
  # so it comes from the `renoise-src` path input (see the header comment);
  # files.renoise.com throttles from this region anyway.
  # The bin wrapper runs under pw-jack so the JACK audio driver joins the
  # shared 48k PipeWire graph (plain ALSA default grabs 44.1k and distorts).
  renoise = finalPrev.renoise.overrideAttrs (old: {
    src = inputs.renoise-src + "/rns_354_linux_x86_64.tar.gz";
    # The nixpkgs installPhase has no runHook postInstall, so wrap the binary
    # in postFixup (fixupPhase always runs it): under pw-jack the JACK audio
    # driver joins the shared 48k PipeWire graph (plain ALSA default grabs
    # 44.1k and distorts).
    postFixup = (old.postFixup or "") + ''
      rm -f $out/bin/renoise
      cat > $out/bin/renoise <<WRAP
      #!${final.stdenv.shell}
      # glib: native u-he VSTs (Diva.64.so) ship against libgio/libgobject,
      # absent from the default loader path on NixOS. pw-jack prepends its own
      # lib dir, so an explicit glib prefix is enough for the plugin loader.
      export LD_LIBRARY_PATH=${final.glib.out}/lib
      exec ${final.pipewire.jack}/bin/pw-jack $out/renoise "\$@"
      WRAP
      chmod +x $out/bin/renoise
    '';
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
    patches = [ ./ouch-valid-unix-perms.patch ];
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

  # pffft: bitbucket.org is RKN-blocked here (DNS-poisoned, sandboxed fetches
  # hang). This override covers direct consumers of pkgs.pffft; vcv-rack's own
  # dep/ fetches are covered by the fetchFromBitbucket override below (same
  # vendored tarball). fuzzysearchdatabase has no top-level nixpkgs attribute
  # (it is a local fetchFromBitbucket call inside vcv-rack's package.nix), so
  # only that interception reaches it — do not add an attribute override for it.
  # (Tarballs are tracked in files/sources/ and referenced by relative path —
  # see the vendored-tarball note above.)
  pffft = finalPrev.pffft.overrideAttrs (_: {
    src = ./../../files/sources/pffft-74d7261.tar.gz;
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
        "jpommier/pffft" = ./../../files/sources/pffft-74d7261.tar.gz;
        "j_norberg/fuzzysearchdatabase" = ./../../files/sources/fuzzysearchdatabase-23122d1.tar.gz;
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

  # Fix keyutils patch download failing (upstream lore.kernel.org 403)
  keyutils = finalPrev.keyutils.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      |> builtins.map (
        p:
        if builtins.isAttrs p && (p.name or "") == "raw" then
          ./../../files/patches/keyutils-fix-format-specifier.patch
        else
          p
      );
  });

  # gsl 2.8: nixpkgs applies a macports patch (fix-linking) fetched from
  # github.com/macports/... raw - that host is blocked/unreachable from this
  # region, so the fixed-output fetch fails. The patch only affects the macOS
  # libtool configure path; vendor the file and keep the rest of the
  # derivation intact (relative-path pattern, see the vendored-tarball note above).
  gsl = finalPrev.gsl.overrideAttrs (_old: {
    # Replace the upstream macports patch fetch (blocked host) with the
    # vendored copy - same content, same extraPrefix.
    patches = [
      (finalPrev.runCommand "gsl-fix-linking.diff" { } ''
        cp ${../../files/sources/gsl-fix-linking.diff} $out
      '')
    ];
  });

}
