{
  lib,
  pkgs,
  inputs,
  impurity ? null,
  ...
}: {
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.path;
      default = inputs.self;
      description = "Root path of the flake repository.";
    };

    rofi.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rofi;
      description = "Primary Rofi package used by system-level wrappers.";
    };
  };

  config.lib.neg = {
    # Impurity link helper (falls back to regular source if impurity is missing)
    linkImpure =
      if (impurity or null) != null
      then impurity.link
      else (x: x);

    # Logic helpers
    mkWhen = lib.mkIf;

    # Nix-maid home file helpers
    mkXdgText = path: text: {
      home."${path}".text = text;
    };

    mkLocalBin = name: text: {
      home.".local/bin/${name}" = {
        inherit text;
        executable = true;
      };
    };
  };
}
