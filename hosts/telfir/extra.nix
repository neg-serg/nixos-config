{lib, inputs, ...}: {
  imports = [(inputs.self + "/modules/diff-closures.nix")];
  diffClosures.enable = true;

  # Workaround Rust packaging issue in lanzaboote by disabling it on this host
  # and using systemd-boot instead. Revert once upstream is fixed.
  boot.lanzaboote.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = true;
}
