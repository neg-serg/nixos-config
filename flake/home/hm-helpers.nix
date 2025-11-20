{
  lib,
  stylixInput,
  chaotic,
  sopsNixInput,
  self,
}: {
  hmBaseModules = {
    profile ? null,
    extra ? [],
  }: let
    homeModule = self + "/home/home.nix";
    base = [
      homeModule
      stylixInput.homeModules.stylix
      chaotic.homeManagerModules.default
      sopsNixInput.homeManagerModules.sops
    ];
    profMod = lib.optional (profile == "lite") (_: {features.profile = "lite";});
  in
    profMod ++ base ++ extra;
}
