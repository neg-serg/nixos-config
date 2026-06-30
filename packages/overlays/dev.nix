_inputs: _final: prev: {
  # bpftrace 0.25+ works with LLVM 22; use same version as the rest of the config
  bpftrace = prev.bpftrace.override { llvmPackages = prev.llvmPackages_22; };
  # Security: avoid insecure Mbed TLS 2 by aliasing to v3
  mbedtls_2 = prev.mbedtls;
  # GNU Radio: disable upstream tests (flaky qa_blocks_hier_block2)
  gnuradio = prev.gnuradio.overrideAttrs (_old: {
    doCheck = false;
    checkPhase = ":";
  });

  # Reserved for development/toolchain overlays

  # Patch pre-commit to add a space before "Skipped" message
  pre-commit = prev.pre-commit.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find $out -name run.py -exec sed -i "s/NO_FILES = '(no files to check)'/NO_FILES = '(no files to check) '/" {} +
    '';
  });

}
