{
  lib,
  neg,
  inputs,
  config,
  ...
}:
{
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.str;
      # flake `self` coerces to its source path; avoids the hardcoded
      # /etc/nixos default and follows the repo wherever it is checked out.
      default = "${inputs.self}";
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
      # absolute one. Replaces fragile ../../../ chains that break when a
      # module moves; use this for files under files/ and secrets/.
      path = p: config.neg.repoRoot + "/" + p;
    };
  };
}
