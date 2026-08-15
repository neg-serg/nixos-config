{
  lib,
  neg,
  config,
  ...
}:
{
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
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
    };
  };
}
