{
  inputs,
  ...
}:
{
  imports = [ (inputs.self + "/modules/diff-closures.nix") ];
  diffClosures.enable = false; # Disabled for faster deploy; use `nix store diff-closures` manually

}
