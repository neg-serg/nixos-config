{ mkBool, ... }:
{
  options.features.apps = {
    throne.enable = mkBool "enable Throne GUI proxy configuration manager" false;
    # ArtCraft suite (VectorCraft, FigCraft, SoundCraft, DeckCraft, GridCraft,
    # SolidCraft): launchers + desktop entries only, every app builds on first
    # launch (modules/user/nix-maid/apps/craft-apps.nix).
    craftApps.enable = mkBool "install the ArtCraft suite as on-demand launchers (vector, design, DAW, slides, sheets, CAD)" false;
  };
}
