{lib, config, ...}:
with lib; {
  imports = [
    ./forensics
    ./pentest
    ./sdr
  ];
  # Hack tooling installs system-wide via modules/dev/hack/*.nix; HM module keeps config hooks only.
}
