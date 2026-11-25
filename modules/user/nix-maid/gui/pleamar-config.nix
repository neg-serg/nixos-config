# pleamar-config (external flake) host glue.
#
# The shell itself — scenes, worker crates, nix-maid units and the login layer —
# lives in github:neg-serg/pleamar-config and is imported in flake/nixos.nix.
# This file only tells it what the host decided: whether the feature flag is on,
# and which checkout the deployed scene links should point at.
#
# `liveRoot` must be the checkout the flake input is taken from
# (`git+file:///home/neg/src/nix/pleamar-config` in flake.nix): the module links
# ~/.config/pleamar/{shells,lib,themes} straight at that directory, so scene
# edits apply without a rebuild. The input type only decides how the module and
# worker sources are pinned, not where the scenes are read from.
{ config, ... }:
{
  pleamar-config.enable = config.lib.neg.pleamarEnabled;
  pleamar-config.liveRoot = "${config.lib.neg.homeDir}/src/nix/pleamar-config";
}
