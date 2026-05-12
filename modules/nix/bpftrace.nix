_: {
  nixpkgs.overlays = [
    (_: prev: {
      bpftrace = prev.bpftrace.override {
        # Force bpftrace to build against an LLVM version it supports (16-20).
        llvmPackages = prev.llvmPackages_20;
      };
    })
  ];
}
