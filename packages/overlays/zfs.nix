inputs: final: prev: {
  # ZFS built from OpenZFS master (supports Linux 7.x kernels)
  zfs = prev.zfs.overrideAttrs (old: {
    version = "master-${builtins.substring 0 7 (inputs.openzfs.rev or "0000000")}";
    src = inputs.openzfs;
    # autoreconfHook already in nativeBuildInputs from nixpkgs generic.nix
  });
}
