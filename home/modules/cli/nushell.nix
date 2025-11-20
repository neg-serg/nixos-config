{
  lib,
  config,
  inputs,
  xdg,
  ...
}:
lib.mkMerge [
  {
    home.activation.removeLegacyNushell = config.lib.neg.mkEnsureAbsent "${config.xdg.configHome}/nushell";
  }
  # Live-editable config via helper (guards parent dir and target)
  (xdg.mkXdgSource "nushell" {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/cli/nushell-conf";
    recursive = true;
  })
  # Provide Nushell module search path via NU_LIB_DIRS, pointing to the nupm modules in the store
  # and the user's local modules directory for overrides.
  {
    home.sessionVariables.NU_LIB_DIRS = lib.concatStringsSep ":" [
      # flake-provided Nushell modules (includes nupm)
      "${inputs.nupm}/modules"
      # user-local modules remain discoverable
      "${config.xdg.configHome}/nushell/modules"
    ];
  }
]
