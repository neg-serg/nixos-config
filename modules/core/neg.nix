{
  lib,
  neg,
  repoRoot,
  config,
  ...
}:
{
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.path;
      # Path literal for the repo root, injected via specialArgs from
      # flake/nixos.nix (real path, not a string — string paths are not
      # tracked in derivation closures and can be garbage-collected).
      default = repoRoot;
      description = "Path to the root of the configuration repository.";
    };

  };

  config = {
    _module.args.mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };

    # Expose helpers under config.lib.neg: the pure neg-helpers from
    # specialArgs (mkHomeFiles, mkLocalBin, ...) extended with uniform
    # feature gating that closes over config.
    lib.neg = neg // {
      # enabled "gui" → features.gui.enable, or false when unset. Sites that
      # previously wrote `or true` (default-on) keep the explicit form.
      enabled =
        path:
        (lib.attrByPath (lib.splitString "." path) { enable = false; } config.features).enable or false;
      gate = path: body: lib.mkIf (config.lib.neg.enabled path) body;

      # Resolve a repo-root-relative path (e.g. "files/gui/theme.toml") to an
      # absolute path. repoRoot is a real path (not a string), so the result
      # carries Nix path context: when used in a derivation or home file it is
      # copied into the store and tracked as a closure dependency — the same
      # behavior as old relative `./../../` references. Do NOT return a plain
      # string here: strings are not added to derivation closures and their
      # files can be garbage-collected away.
      #
      # NB: keep the leading slash inside the same string operand —
      # `path + "/"` normalizes the trailing slash away and the join breaks.
      path = p: config.neg.repoRoot + ("/" + p);

      # Existence check for optional repo files (no eval error when missing).
      pathExists = p: builtins.pathExists (config.neg.repoRoot + ("/" + p));
    };
  };
}
