_inputs: final: prev:
let
  call = final.neg.functions.callPkg;
  pkg = final.neg.functions.pkg;
in
{
  # bpftrace 0.25+ works with LLVM 22; use same version as the rest of the config
  bpftrace = prev.bpftrace.override { llvmPackages = prev.llvmPackages_22; };
  # Security: avoid insecure Mbed TLS 2 by aliasing to v3
  mbedtls_2 = prev.mbedtls;
  # GNU Radio: disable upstream tests (flaky qa_blocks_hier_block2)
  gnuradio = prev.gnuradio.overrideAttrs (_old: {
    doCheck = false;
    checkPhase = ":";
  });

  # The nixie workbench: the login clock's tubes drawn off-screen on the GPU
  # (packages/nixie/, run as `nixie validate|render|sweep`), so their geometry
  # and their discharge can be checked without a compositor in the way.
  nixie = call (pkg "nixie") { };

  # Candidate Nix build: nixpkgs' 2.35 + upstream #16244 + the nine
  # evaluation-speedup patches (see packages/nix-eval-patched/default.nix).
  # Deliberately not wired into `nix.package` — it is a measurement/candidate
  # artifact, and it lacks Determinate's lazy-trees (the caveat is in the
  # package's header comment).
  nix-eval-patched = call (pkg "nix-eval-patched") { };

  # Determinate Nix 3.23.3 rebuilt with PGO + the five evaluation-speedup
  # patches their tree accepts (see packages/nix-det-pgo/default.nix). The one
  # candidate that keeps lazy-trees, so this is what
  # `features.nix.pgoNix.enable` puts in `nix.package` (off by default;
  # modules/nix/nix-pgo.nix).
  nix-det-pgo = call (pkg "nix-det-pgo") { };

  # Reserved for development/toolchain overlays

  # Patch pre-commit to add a space before "Skipped" message
  pre-commit = prev.pre-commit.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find $out -name run.py -exec sed -i "s/NO_FILES = '(no files to check)'/NO_FILES = '(no files to check) '/" {} +
    '';
  });
}
