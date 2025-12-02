{
  lib,
  config,
  ...
}:
lib.mkIf config.features.dev.enable {
  nixpkgs = {
    config.packageOverrides = super: {
      python3-lto = super.python3.override {
        packageOverrides = _: _: {
          enableOptimizations = true;
          enableLTO = true;
          reproducibleBuild = false;
        };
      };
    };
  };
  # Python runtimes now install via modules/dev/python/pkgs.nix at the system level.
}
