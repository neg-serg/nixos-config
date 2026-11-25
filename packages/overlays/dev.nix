inputs: final: prev: {
  # bpftrace 0.25+ works with LLVM 22; use same version as the rest of the config
  bpftrace = prev.bpftrace.override { llvmPackages = prev.llvmPackages_22; };
  # Security: avoid insecure Mbed TLS 2 by aliasing to v3
  mbedtls_2 = prev.mbedtls;
  # GNU Radio: disable upstream tests (flaky qa_blocks_hier_block2)
  gnuradio = prev.gnuradio.overrideAttrs (_old: {
    doCheck = false;
    checkPhase = ":";
  });

  # The two Nix builds call `prev.callPackage`, not `final`: the package reads
  # `pkgs.nixDependencies` and the modular nix components, and moving the
  # fixpoint changed every component derivation even though the output tree is
  # the same (a 12-minute PGO rebuild). Keep the call shape the packages had
  # when they lived in packages/.
  # Candidate Nix build: nixpkgs' Nix + upstream #16244 + the evaluation-speedup
  # patch stack. Owned by github:neg-serg/nix-optimized (live checkout
  # ~/src/nix/nix-optimized); this overlay keeps the `pkgs.neg` name and builds
  # it against this package set. Deliberately not wired into `nix.package` — it
  # is a measurement/candidate artifact, and it lacks Determinate's lazy-trees
  # (the caveat is in the package's header comment).
  nix-eval-patched = prev.callPackage (inputs.nix-optimized + "/nix-eval-patched/package.nix") { };

  # Determinate Nix 3.23.3 rebuilt with PGO + the five evaluation-speedup
  # patches their tree accepts (github:neg-serg/nix-optimized). The one
  # candidate that keeps lazy-trees, so this is what
  # `features.nix.pgoNix.enable` puts in `nix.package` (off by default;
  # modules/nix/nix-pgo.nix).
  nix-det-pgo = prev.callPackage (inputs.nix-optimized + "/nix-det-pgo/package.nix") {
    inherit (inputs) nix-src;
  };

  # llama.cpp with the Inkling-2-Mini looped-layer fix (#32704, still open) —
  # a second binary beside the stable `llama-cpp-vulkan`, used by the Inkling
  # tier only. The header of packages/llama-cpp-inkling/default.nix carries the
  # why and the removal condition.

  # Reserved for development/toolchain overlays

  # Patch pre-commit to add a space before "Skipped" message
  pre-commit = prev.pre-commit.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find $out -name run.py -exec sed -i "s/NO_FILES = '(no files to check)'/NO_FILES = '(no files to check) '/" {} +
    '';
  });
}
