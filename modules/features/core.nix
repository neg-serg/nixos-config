{ mkBool, ... }:
{
  options.features = {
    # NOTE: `features.profile` (singular) removed — was dead code.
    # Use `features.profiles` (plural, list) for profile composition.

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;

    # Distributed builds: hand builds to a second x86_64 machine over SSH
    # (modules/nix/distributed-build.nix). Off-quiet: when the builder is
    # unreachable Nix warns and builds locally.
    nix.remoteBuilder.enable = mkBool "send builds to the Hetzner VPS (late.sh) over SSH" true;
  };
}
