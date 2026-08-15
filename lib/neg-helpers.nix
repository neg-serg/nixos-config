# Structural home-file helpers — pure functions with no config dependency.
# Single source of truth: flake/nixos.nix (specialArgs.neg) and
# flake/checks.nix import this file instead of inlining or stubbing them.
{
  # Home files for the primary user, applied via nix-maid (users.users.neg.maid)
  mkHomeFiles = files: {
    users.users.neg.maid.file.home = files;
  };

  # A single home file with text content
  mkXdgText = path: text: {
    home."${path}".text = text;
  };

  # An executable script under ~/.local/bin
  mkLocalBin = name: text: {
    home.".local/bin/${name}" = {
      inherit text;
      executable = true;
    };
  };

  # Pass-through for impure values
  linkImpure = x: x;
}
