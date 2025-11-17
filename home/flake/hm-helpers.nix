{
  lib,
  stylixInput,
  chaotic,
  sopsNixInput,
}: {
  hmBaseModules = {
    profile ? null,
    extra ? [],
  }: let
    base = [
      ../home.nix
      stylixInput.homeModules.stylix
      chaotic.homeManagerModules.default
      sopsNixInput.homeManagerModules.sops
    ];
    profMod = lib.optional (profile == "lite") (_: {features.profile = "lite";});
  in
    profMod ++ base ++ extra;
}
