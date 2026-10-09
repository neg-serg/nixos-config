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
        (_final: prev: {
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
        })
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
        # Rebuild buildFHSEnv from the stock nixpkgs one (instead of the composed,
        # wrapped one) and inject the /sbin/ldconfig Steam RT3 fix here.
        #
        # Applied last so it wins over both broken wrappers.
        (_final: _prev: {
          buildFHSEnv =
            let
              # Stock nixpkgs buildFHSEnv, but with allowUnfree so steam's FHS
              # env (which includes the unfree steam-unwrapped) evaluates.
              orig =
                (import inputs.nixpkgs {
                  inherit system;
                  config.allowUnfree = true;
                }).buildFHSEnv;
              ldconfigFix = ''
                if [ -L $out/usr/sbin/ldconfig ] && [ -f $out/usr/bin/ldconfig ]; then
                  cp -f $out/usr/bin/ldconfig $out/usr/sbin/ldconfig
                fi
              '';
            in
            args:
            orig (
              if builtins.isFunction args then
                (
                  final:
                  (args final) // { extraBuildCommands = ((args final).extraBuildCommands or "") + ldconfigFix; }
                )
              else
                (args // { extraBuildCommands = (args.extraBuildCommands or "") + ldconfigFix; })
            );
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
