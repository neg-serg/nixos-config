# nix-det-pgo: Determinate Nix 3.23.3 (nix-src v3.23.3 = flake input `nix-src`,
# commit 74d688aa, upstream 2.35.3 lineage) rebuilt with profile-guided
# optimisation plus the evaluation-speedup patches that survive Determinate's
# tree, so `nix.package` can be swapped for a binary that evaluates this repo
# faster than stock Determinate while *keeping* lazy-trees.
#
# The machinery is ~/src/nix-optimized/nix/default.nix (nix-optimized): an
# instrumented build, a training run that records counters, then a
# `-fprofile-use` build from the collected profile. Same cycle here, applied to
# Determinate's source instead of upstream's, plus the five patches and the
# packaging shims their tree needs (libgit2/bdwgc forks, wasm/sentry/otel off).
#
# Measured (trantor, toplevel drvPath eval on /etc/nixos, 6 runs each,
# interleaved A/B):
#   stock Determinate 3.23.3   8.85 s / 8.17 s
#   this package, PGO only     7.84 s / 7.39 s   (-11 %)
#   this package + patches     7.26 s / 6.97 s   (-18 %)
# End to end `nix eval` on /etc/nixos: 7.8–8.2 s against the system's 9.0 s, and
# the resulting drvPath is identical to the system Nix's. Dropping the `patches`
# list below reproduces the PGO-only control.
#
# Re-measured through this package after it was folded into the tree (same
# method: 6 interleaved rounds, one eval cache per binary, drvPath as the
# oracle): stock Determinate 3.23.3 median 8.59 s, this build median 7.32 s
# (-14.9 %), every binary producing the same toplevel drvPath. The gain is
# smaller than the prototype's -18 % because the nixpkgs pin moved between the
# two measurements (the prototype built against a 26.11 snapshot whose own nix
# attr is 2.35.2, this tree against rev 1c89083 where it is 2.35.3), so
# compiler, stdenv and the component closures are all newer.
#
# lazy-trees survives by construction: none of the five patches touches
# eval-settings.hh, so the setting table and its defaults are Determinate's own
# — `nix config show` keeps `lazy-trees = true`, and eval-cache/parallel-eval
# keep working. (This is the difference to packages/nix-eval-patched, which is
# upstream Nix and does not know the setting.)
#
# BOLT is deliberately absent. Run with BOLT (instrument, train, boltify every
# libnix*.so) the profile run collected zero .fdata on this tree, so the extra
# builds plus the --emit-relocs/strip overrides bought nothing; it must stay
# off. The plain PGO stages are what the numbers above come from.
#
# Cost: ~12 min per Determinate version on this host — two instrumented builds,
# two training runs, one profile-use build, plus the patched components.
#
# On a Determinate bump (the `nix-src` flake input, which the system's own
# nix.package follows; bump `determinate` with it):
#   - the profile retrains itself: the workload is in-repo (./workload.nix,
#     instantiate-only) and the profile is generated inside the derivation
#     (pgoProfile below, profile data never leaves the build), so no data,
#     counter set or hash needs upkeep;
#   - the five patches must be re-dry-run against the new tree
#     (`patch -p1 --dry-run` in the bumped source): they are cut against
#     upstream 2.35 and Determinate carries its own commits on top;
#   - the packaging shims must be re-validated: -Dwasm/-Dsentry/-Dotel=disabled,
#     sqlite in libexpr and libmicrohttpd in the CLI, Determinate's libgit2
#     (rev + hash below) and bdwgc (`bdwgc` flake input) forks, and the
#     `determinate-nix-store` meson build-dir override that
#     modules/nix/settings.nix already applies to nix.package — a rename of that
#     `pname` makes the override silently stop applying.
{
  lib,
  pkgs,
  inputs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  # The nix version Determinate's 3.23.3 is cut from; the patch count shows up
  # as the `+N` suffix in the store name and in `nix --version`.
  version = "2.35.3";

  # Sources pinned the way the tree passes them around: `nix-src` *is* a
  # top-level flake input (the same rev the system's own nix.package follows),
  # so it arrives as an input. The two forks an input does not carry are fetched
  # here by commit — `bdwgc` is only a transitive input of nix-src, so it is not
  # in scope, and libgit2 is not a flake input at all.
  detSrc = inputs.nix-src.outPath;

  # bdwgc's user-defined-stack API (GC_get_approx_sp, GC_stack) only exists in
  # Determinate's fork; same rev as the `bdwgc` node nix-src locks.
  bdwgcSrc = pkgs.fetchFromGitHub {
    owner = "DeterminateSystems";
    repo = "bdwgc";
    rev = "d569c29c479acb44bcf4e992acfc776fb88fb857";
    hash = "sha256-Wip2gE+2EJGC6trYxO9Pl36rkgA3BJJkAsiWTVGXFBc=";
  };

  # Determinate's libfetchers calls git_config_backend_from_values(), which does
  # not exist in libgit2 1.9.x, so the build needs their 2.0.0-rc.1 fork
  # (ae45d0d). Pinned by commit, not tag: the release tag predates the
  # packaging fixes their tree applies on top.
  libgit2Src = pkgs.fetchFromGitHub {
    owner = "DeterminateSystems";
    repo = "libgit2";
    rev = "ae45d0d168f7e8dbfdb8c623589cb51caac96ab3";
    hash = "sha256-3sbqHm37SOwBeFgtjI2DLN6kx1F7G2N1m6rRIkqDXNI=";
  };

  # Where the instrumented build drops its counters. GCC bakes this string into
  # the objects, so it must be identical in both builds and must not carry a
  # host path: /build is NIX_BUILD_TOP in every Nix sandbox, i.e. still inside
  # the derivation, and the profile is copied to pgoProfile's $out before the
  # build directory is thrown away.
  generateDir = "/build/pgo-gcda";

  # The five patches from ~/src/nix-optimized/patches/2.35/ that apply cleanly
  # here. Byte-identical to the same-named files in
  # packages/nix-eval-patched/patches/ (that package holds the whole nine-patch
  # stack for upstream Nix; this one only carries what Determinate's tree
  # accepts).
  #
  # Deliberately absent — do not attempt them on this tree:
  #   0002 (skip IsValidPath for paths pinned and valid), 0006 (memoize
  #     derivationStrict) — conflict with Determinate's async writer;
  #   0007 (skip re-adding builtins.toFile paths) — conflicts with its batched
  #     temp roots;
  #   0008 (pipeline AddTempRoot and IsValidPath) — rewrites that same batched
  #     temp-root code and is useless here.
  patches = [
    ./patches/0001-libstore-unparse-structured-attrs-without-copying-th.patch
    ./patches/0003-libexpr-reuse-the-memoized-derivation-hash-for-a-rep.patch
    ./patches/0004-libutil-check-the-allow-list-predecessor-before-walk.patch
    ./patches/0005-libexpr-use-constant-error-contexts-in-builtins.any-.patch
    ./patches/0009-libfetchers-refresh-the-cached-git-HEAD-after-readin.patch
  ];

  # The instrumented build must not use -Db_lto: Determinate builds with LTO,
  # and with LTO the per-TU counters are only created at the LTO link step, so
  # the instrumented binary ends up (almost) uncounted. Turning LTO off for the
  # instrumented build only affects profile collection, not the final build.
  noLto =
    nix:
    nix.overrideAllMesonComponents (
      _: prevAttrs: {
        mesonFlags = lib.filter (f: !(lib.hasPrefix "-Db_lto" f)) (prevAttrs.mesonFlags or [ ]) ++ [
          "-Db_lto=false"
        ];
      }
    );

  withFlags =
    flags: nix:
    nix.overrideAllMesonComponents (
      _: prevAttrs: {
        env = (prevAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = flags;
        };
      }
    );

  # The same splices that nixpkgs' nixVersions.nixComponents_2_35 is built with.
  spliceOf =
    a: lib.attrByPath (lib.splitString "." a) (throw "nix-det-pgo: missing splice ${a}") pkgs;
  otherSplices = {
    selfBuildBuild = spliceOf "pkgsBuildBuild.nixVersions.nixComponents_2_35";
    selfBuildHost = spliceOf "pkgsBuildHost.nixVersions.nixComponents_2_35";
    selfBuildTarget = spliceOf "pkgsBuildTarget.nixVersions.nixComponents_2_35";
    selfHostHost = spliceOf "pkgsHostHost.nixVersions.nixComponents_2_35";
    selfHostTarget = spliceOf "pkgsHostTarget.nixVersions.nixComponents_2_35";
    selfTargetTarget =
      lib.attrByPath (lib.splitString "." "pkgsTargetTarget.nixVersions.nixComponents_2_35") { }
        pkgs;
  };

  components =
    pkgs.nixDependencies.callPackage
      (pkgs.path + "/pkgs/tools/package-management/nix/modular/packages.nix")
      {
        inherit version otherSplices;
        src = detSrc;
        teams = [
          lib.teams.nix
          lib.teams.security-review
        ];
      };

  # nixpkgs packaging, but every component builds from Determinate's tree.
  # Determinate's libstore/libexpr have a `wasm` feature option (wasmtime
  # integration). nixpkgs' generic build enables every auto feature, and the
  # wasmtime C++ headers (<wasmtime.hh>) are not in nixpkgs, so turn the option
  # off for those two components. It is unrelated to evaluation.
  noWasm =
    comps:
    comps.overrideScope (
      _: prev: {
        nix-store = prev.nix-store.overrideAttrs (o: {
          mesonFlags = (o.mesonFlags or [ ]) ++ [ "-Dwasm=disabled" ];
        });
        boehmgc = boehmgcDet;
        # Sentry crash reporting and OTLP tracing need Determinate's vendored
        # sentry-native/crashpad/opentelemetry forks; they are unrelated to
        # evaluation, so leave them off instead of pulling that tree in.
        nix-cli = prev.nix-cli.overrideAttrs (o: {
          mesonFlags = (o.mesonFlags or [ ]) ++ [
            "-Dsentry=disabled"
            "-Dotel=disabled"
          ];
          # Determinate's CLI serves its own Prometheus metrics endpoint.
          buildInputs = (o.buildInputs or [ ]) ++ [ pkgs.libmicrohttpd ];
        });
        nix-expr = prev.nix-expr.overrideAttrs (o: {
          mesonFlags = (o.mesonFlags or [ ]) ++ [ "-Dwasm=disabled" ];
          # nixpkgs only adds sqlite for >= 2.36pre; Determinate's tree (2.35.3
          # + their own commits) already links libnixexpr against it.
          buildInputs = (o.buildInputs or [ ]) ++ [ pkgs.sqlite ];
        });
      }
    );

  libgit2Det = pkgs.libgit2.overrideAttrs (prevAttrs: {
    version = "2.0.0-rc.1";
    src = libgit2Src;
    patches = (prevAttrs.patches or [ ]) ++ [
      (detSrc + "/packaging/patches/0002-memory-config.patch")
      (detSrc + "/packaging/patches/0003-packbuilder-correct-config.patch")
      (detSrc + "/packaging/patches/libgit2-packbuilder-dont-fail-on-thread-create-error.patch")
    ];
    separateDebugInfo = true;
    meta = builtins.removeAttrs prevAttrs.meta [ "changelog" ];
  });

  # Determinate's libexpr needs bdwgc's user-defined-stack API
  # (GC_get_approx_sp, GC_stack), which only exists in their fork
  # (`bdwgc` flake input, branch user-defined-stacks), together with the
  # tunables from packaging/dependencies.nix.
  boehmgcDet =
    (pkgs.nixDependencies.boehmgc.override {
      enableLargeConfig = true;
      inherit (pkgs) stdenv;
    }).overrideAttrs
      (attrs: {
        src = bdwgcSrc;
        nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [ pkgs.buildPackages.autoreconfHook ];
        env = (attrs.env or { }) // {
          NIX_CFLAGS_COMPILE = toString [
            "-DINITIAL_MARK_STACK_SIZE=1048576"
            "-DGC_MANY_BLOCKS_DEFAULT=64"
            "-DNO_BLACK_LISTING"
            "-DGC_TINY_FREELISTS=96"
          ];
        };
      });

  nixPkg =
    ((noWasm (components.overrideScope (_: _: { libgit2 = libgit2Det; }))).appendPatches patches)
    .nix-everything;

  # One training run: instantiate (evaluate, never build) a slice of nixpkgs
  # plus two NixOS release closures — the same code path as this repo's own
  # toplevel eval. See ./workload.nix.
  train = nix: ''
    export NIX_STATE_DIR=$TMPDIR/state
    export NIX_CONFIG="extra-experimental-features = nix-command"
    ${nix}/bin/nix-env -qaP --json -f ${pkgs.path} -A python3Packages > /dev/null
    ${nix}/bin/nix eval --read-only --raw --impure --expr \
      'import ${./workload.nix} { nixpkgs = ${pkgs.path}; system = "${system}"; }'
  '';

  optimize =
    nix:
    let
      # Determinate's quickExit() calls std::_Exit() (skipping atexit handlers,
      # and with them libgcov's dump) unless __LLVM_INSTR_PROFILE_GENERATE is
      # defined; define it so the profile counters are actually written.
      instrumented =
        (noLto (withFlags "-fprofile-generate=${generateDir} -D__LLVM_INSTR_PROFILE_GENERATE=1" nix))
        .overrideAttrs
          {
            doCheck = false;
          };
      pgoProfile = pkgs.runCommand "nix-det-pgo-profile" { } ''
        export GCOV_PREFIX=$TMPDIR/gcov
        ${train instrumented}
        mkdir $out
        # GCC records '<generateDir>/<absolute build path>/<obj>.gcda', so keep
        # the directory structure (the -fprofile-use build unpacks to the same
        # /build path).
        cp -a $GCOV_PREFIX${generateDir}/. $out/
      '';
      pgo = withFlags "-fprofile-use=${pgoProfile} -fprofile-correction -fprofile-partial-training -fno-reorder-blocks-and-partition" nix;
    in
    pgo.overrideAttrs (prevAttrs: {
      # Same choice modules/nix/settings.nix makes for nix.package: Determinate's
      # own test suite gates the build on nix-*-tests-run inputs, and a subset of
      # those tests (IPv6 zone-id URL parsing) fails on their tree regardless of
      # this package. Turning doCheck on would therefore fail the build on a
      # failure this package did not cause, so the patches are accepted by
      # behaviour instead, in three layers:
      #   1. the toplevel drvPath matches the stock binary on the same tree
      #      (measured repeatedly, including the -18 % A/B runs);
      #   2. a differential battery runs stock against this build and compares
      #      output byte for byte: builtins.any/all, a structuredAttrs drvPath,
      #      `nix hash path`, fromJSON/toJSON, path canonicalisation and
      #      `nix flake metadata --json` — all identical on 2026-11-02;
      #   3. `scripts/dev/nix-memo-diff.sh` covers the memoisation patch for the
      #      upstream build (packages/nix-eval-patched), where doCheck is on.
      # What none of this proves: that a patch behaves right in a code path the
      # battery does not touch. That is the price of shipping a build whose own
      # suite cannot go green on this source tree.
      doCheck = false;

      passthru = (prevAttrs.passthru or { }) // {
        inherit instrumented pgoProfile;
      };

      # Keep nixpkgs' own meta (homepage, platforms, teams) — it *is* that
      # package, only rebuilt from Determinate's tree — but drop the upstream
      # maintainer list: nothing here is upstream, per packages/AGENTS.md.
      meta = prevAttrs.meta // {
        description = "Determinate Nix ${version} rebuilt with PGO and evaluation-speedup patches";
        maintainers = [ ];
      };
    });
in
optimize nixPkg
