let
  cat = import ./unfree/categories.nix;
  forensics = cat."forensics-stego" ++ cat."forensics-analysis";
in
{
  # Desktop-oriented unfree packages (composed from categories)
  desktop = cat.audio ++ cat."ai-tools" ++ cat.browsers ++ forensics ++ cat.misc;

  # Headless/server preset: no unfree packages allowed
  headless = [ ];
}
