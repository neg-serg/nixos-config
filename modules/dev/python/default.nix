{ lib, ... }:
{
  nixpkgs = {
    hostPlatform = lib.mkDefault "x86_64-linux";
    config.allowUnfree = true;

    config.packageOverrides = super: {
      python3-lto = super.python3.override {
        packageOverrides = _pythonSelf: _pythonSuper: {
          enableOptimizations = true;
          enableLTO = true;
          reproducibleBuild = false;
        };
      };
    };
  };
  imports = [ ./pkgs.nix ];
}
