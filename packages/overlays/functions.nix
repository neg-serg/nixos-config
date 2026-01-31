_inputs: _final: prev: {
  # Shared helper functions under pkgs.neg.functions to DRY up overlay patterns
  neg = (prev.neg or { }) // {
    functions = {
      # Override the Python package scope with a function (self: super: { ... })
      # Usage in an overlay:
      #   python3Packages = pkgs.neg.functions.overridePyScope (self: super: {
      #     foo = super.foo.overrideAttrs (_: { ... });
      #   });
      overridePyScope = f: prev.python3Packages.overrideScope f;

      # Small helper to override attrs of a derivation
      # withOverrideAttrs drv f = drv.overrideAttrs f
      withOverrideAttrs = drv: f: drv.overrideAttrs f;

      # Generic helper: overrideScope for a top-level package set by name
      # Returns an attrs set you can merge in an overlay.
      # Example usage in overlay file:
      #   _final.neg.functions.overrideScopeFor "python3Packages" (self: super: {
      #     ncclient = super.ncclient.overrideAttrs (_: { src = ...; });
      #   })
      overrideScopeFor =
        name: f:
        if (prev ? ${name}) && (prev.${name} ? overrideScope) then
          { ${name} = prev.${name}.overrideScope f; }
        else
          { };

      # --- Language-specific convenience helpers ---
      # Rust (buildRustPackage): override cargo hash (aka vendor hash)
      # Works with both cargoHash (new) and cargoSha256 (legacy)
      overrideRustCrates =
        drv: hash:
        drv.overrideAttrs (_: {
          cargoHash = hash;
          cargoSha256 = hash;
        });

      # Go (buildGoModule): override vendor hash
      overrideGoModule =
        drv: hash:
        drv.overrideAttrs (_: {
          vendorHash = hash;
        });

      # Autoreconf helper: ensure autoreconf and required autotools are available
      # Adds autoreconfHook and common tools to nativeBuildInputs.
      withAutoreconf =
        drv:
        drv.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            prev.autoreconfHook
            prev.autoconf
            prev.automake
            prev.libtool
            prev.pkg-config
            prev.gettext
          ];
        });

      # CMake: enforce a minimum policy version to keep older projects
      # working with newer CMake releases.
      # Appends -DCMAKE_POLICY_VERSION_MINIMUM=3.5 to cmakeFlags.
      withCMakePolicyFloor =
        drv:
        drv.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
        });

      # Zen 5 Optimization Helper (Clang + Zen 5)
      # Usage: pkgs.neg.functions.mkZen5LtoPackage pkgs.somePackage
      mkZen5LtoPackage =
        drv:
        (drv.override {
          stdenv = prev.llvmPackages_19.stdenv;
        }).overrideAttrs
          (old: {
            # LTO disabled due to linker issues (archive has no index)
            # cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE" ];

            # Force Clang to use Zen 4 instructions (compatible with Zen 5, better cache hit rate)
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE = toString [
                "-march=znver4"
                # "-flto=thin" # Disabled
                "-mprefer-vector-width=512" # Leverage reliable AVX-512 on Zen 4/5
                "-Wno-error"
              ];
              # NIX_LDFLAGS = "-flto=thin"; # Disabled
            };
          });
    };
  };
}
