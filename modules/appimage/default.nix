{ pkgs, ... }:
{
  # run appimages directly (see https://nixos.wiki/wiki/Appimage)
  # appimage-run available via `nix shell nixpkgs#appimage-run`
  boot.binfmt.registrations.appimage = {
    wrapInterpreterInShell = false;
    interpreter = "${pkgs.appimage-run}/bin/appimage-run";
    recognitionType = "magic";
    offset = 0;
    mask = "\\xff\\xff\\xff\\xff\\x00\\x00\\x00\\x00\\xff\\xff\\xff";
    magicOrExtension = "\\x7fELF....AI\\x02";
  };
}
