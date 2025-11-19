{lib, config, ...}:
with lib; {
  imports = [
    ./forensics
    ./pentest
    ./sdr
    ./vulnerability_scanners.nix
  ];
  # Hack tooling installs system-wide via modules/dev/hack/*.nix; HM module keeps config hooks only.
}
