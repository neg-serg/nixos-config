{ neg, ... }:
{
  # Per-theme user units live in ./user-services/*.nix. `sys/default.nix` imports
  # flat files only (importDir without includeDirs), so this file is the entry
  # point that pulls the themed siblings in.
  imports = neg.importDir { dir = ./user-services; };
}
