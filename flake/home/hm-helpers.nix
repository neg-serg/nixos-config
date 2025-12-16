{
  lib,
  self,
  stylixInput,
  sopsNixInput,
}: {
  hmBaseModules = {
    profile ? null,
    extra ? [],
  }: let
    homeModule = self + "/home/home.nix";
    base = [
      homeModule
      stylixInput.homeModules.stylix
      sopsNixInput.homeManagerModules.sops
    ];
    profMod = lib.optional (profile == "lite") (_: {features.profile = "lite";});
  in
    profMod ++ base ++ extra;
}
