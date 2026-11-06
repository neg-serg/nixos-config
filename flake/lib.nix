{ inputs, nixpkgs, ... }:
let
  # NOTE: hy3 comes from nixpkgs 26.05 (0.55.0), built against the same
  # Hyprland 0.55.4 the system ships. The github:outfoxxed/hy3 flake input
  # tracked Hyprland 0.56+ and its .so failed to load here (undefined symbol
  # IModeAlgorithm::getFSHandler); it was never used, so the input is gone
  # (audit 2026-09-15) and hyprlandPlugins stays exactly as nixpkgs ships it.

  bintoolsBootstrapFix = _: prev: {
    bintools = prev.bintools // {
      passthru = (prev.bintools.passthru or { }) // {
        isFromBootstrapFiles =
          (prev.bintools.passthru.bintools.passthru.isFromMinBootstrap or false)
          || (prev.bintools.passthru.bintools.passthru.isFromBootstrapFiles or false);
      };
    };
  };

  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      # Allow only the few proprietary packages the user asked for —
      # everything else stays unfree-blocked: VST2 SDK (needed by vstplugin,
      # the SuperCollider VST host), lsfg-vk, and Geekbench AI.
      config.allowUnfreePredicate =
        pkg:
        (pkg.pname or "") == "vst2-sdk"
        || (pkg.pname or "") == "lsfg-vk" # CC BY-NC-ND 4.0 (user-approved install)
        || (pkg.pname or "") == "geekbench-ai"; # proprietary AI benchmark (user-requested install)
      overlays = [
        bintoolsBootstrapFix
        # The session starts the compositor without uwsm: `programs.hyprland`
        # defaults `withUWSM` to false on 0.57, and start-hyprland is called
        # directly. `pkgs.hyprland` would otherwise keep the default uwsm build,
        # so every helper that references it (hyprctl wrappers, user units, the
        # login plugin) pulled a second compositor build into the closure. Pin
        # the package set to the build the session runs; the module's own
        # `override { withUWSM = false; }` is idempotent on top of it.
        (_final: prev: {
          hyprland = prev.hyprland.override { withUWSM = false; };
        })
        # CachyOS kernel packages — overlays.default builds against OUR nixpkgs
        # rev (the pinned overlay would hijack the whole flake nixpkgs pin and
        # break the Hyprland 0.56.2 setup); kernels are exposed as pkgs.cachyosKernels.*.
        inputs.nix-cachyos-kernel.overlays.default
        # xdg-desktop-portal-hyprland deliberately comes from nixpkgs: since
        # 1.4.1 it carries the event-loop busy-spin fix (upstream #417 "core:
        # fix loop hangup detection"). The former flake pin (rev 08d99f72 =
        # 1.4.0) silently downgraded the nixpkgs package and burned ~160% CPU.
        # Local overlay first (for packages not yet migrated)
        ((import ../packages/overlay.nix) inputs)
        # External package flake (github:neg-serg/nixos-pkgs)
        inputs.neg-pkgs.overlays.default
        # Last overlay wins: neg-pkgs defines python3-lto from prev.python3
        # and drops the untangle src override, so re-apply the vendored-source
        # fix here (upstream tag was re-pushed → hash mismatch otherwise).
        # It also still ships its python-era pretty-printer there, and that one
        # has no `vid-info`, so the nix-maid link in cli/local-bin.nix dangles.
        # Re-assert the local Rust port from packages/ — the overlay above loses
        # to this one for the whole `neg` attribute set.
        (
          _final: prev:
          let
            prettyPrinter = _final.callPackage ../packages/pretty-printer { };
          in
          {
            neg = (prev.neg or { }) // {
              # neg-pkgs still ships brrtfetch without -trimpath, so the Go
              # toolchain stays in the runtime closure; re-assert our copy.
              brrtfetch = _final.callPackage ../packages/brrtfetch { };
              pretty_printer = prettyPrinter;
              "pretty-printer" = prettyPrinter;
            };
            python3-lto = prev.python3.override {
              packageOverrides = _pythonSelf: _pythonSuper: {
                enableOptimizations = true;
                enableLTO = true;
                reproducibleBuild = false;
                untangle = _pythonSuper.untangle.overrideAttrs (_: {
                  src = ../files/sources/untangle-1.2.1.tar.gz;
                });
                distutils = _pythonSuper.distutils.overrideAttrs (_o: {
                  doCheck = false;
                });
              };
            };
          }
        )
        # onetbb's test suite is flaky under the nix builder (SIGABRT in
        # concurrency tests: test_collaborative_call_once, test_concurrent_vector,
        # test_task_arena ...). The library builds fine; only its tests crash
        # intermittently, which fails the build. Disable check so it builds
        # deterministically.
        (_final: prev: {
          onetbb = prev.onetbb.overrideAttrs (_old: {
            doCheck = false;
          });
        })
        # distutils' own test suite fails under the nix builder with
        # "RuntimeError: can't start new thread" (concurrent-thread tests).
        # scons (and others) pull python3Packages.distutils directly; force
        # doCheck=false + a no-op checkPhase at the python3Packages package-set
        # level so every consumer builds distutils without the failing tests.
        (_final: prev: {
          python3Packages = prev.python3Packages.overrideScope (
            _pythonSelf: _pythonSuper: {
              distutils = _pythonSuper.distutils.overrideAttrs (_o: {
                doCheck = false;
                checkPhase = "echo 'distutils tests disabled (can\\'t start new thread)'";
              });
            }
          );
        })
        # pipewire builds FFADO (FireWire) and ROC support by default. FFADO
        # pulls scons + a python3 env whose distutils tests fail with "can't
        # start new thread" under the nix builder. Neither FFADO nor ROC
        # streaming is needed on this host; disable both so pipewire builds
        # without the ffado/roc/scons/distutils chain.
        (_final: prev: {
          pipewire = prev.pipewire.override {
            ffadoSupport = false;
            rocSupport = false;
          };
        })
        # nixos-unstable (0.56) rewrote buildFHSEnv on lib.extendMkDerivation
        # (fixed-point __functor: the argument may be a config set OR a function).
        # The older wrappers in packages/overlay.nix and neg-serg/nixos-pkgs do
        # `args: prev.buildFHSEnv (args // {...})`, which throws "expected a set
        # but found a function" when called with the new function-style argument.
        #
        # This overlay is last, so it wins over both wrappers. It re-calls the
        # stock nixpkgs implementation against THIS fixpoint: `prev.callPackage`
        # binds `pkgsHostTarget` (what multiPkgs/targetPkgs are called with) to
        # prev, which is final for every package except buildFHSEnv itself. The
        # /sbin/ldconfig Steam RT3 fix is kept for both argument styles.
        #
        # Before this, the stock function came from a fresh
        # `import inputs.nixpkgs { config.allowUnfree = true; }`: a second
        # evaluation of nixpkgs without the flake overlays. Every FHS package an
        # overlay changes (llvm, mesa, the fonts, the python toolchain) was built
        # twice — once for the system, once for the FHS env — and the duplicates
        # sat in the system closure beside their originals.
        (_final: prev: {
          buildFHSEnv =
            let
              stock = prev.callPackage (prev.path + "/pkgs/build-support/build-fhsenv-bubblewrap") { };
              ldconfigFix = ''
                if [ -L $out/usr/sbin/ldconfig ] && [ -f $out/usr/bin/ldconfig ]; then
                  cp -f $out/usr/bin/ldconfig $out/usr/sbin/ldconfig
                fi
              '';
              fix =
                a:
                a
                // {
                  extraBuildCommands = (a.extraBuildCommands or "") + ldconfigFix;
                };
            in
            args: stock (if builtins.isFunction args then (pkgs: fix (args pkgs)) else fix args);
        })
      ];
      config = {
        allowAliases = false;
        allowUnfree = true;
        doCheckByDefault = false;
        permittedInsecurePackages = [ "pzip-0.2.0" ];
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };

  # Wrap a devshell module's argument set into `pkgs.mkShell`. Every
  # `flake/devshells/*.nix` module returns such an argument set, so the
  # `mkShell` call (and any future shared defaults) lives in one place.
  mkDevShell = pkgs: args: pkgs.mkShell args;
in
{
  inherit mkPkgs mkCustomPkgs mkDevShell;
}
