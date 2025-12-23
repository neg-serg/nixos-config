{pkgs, ...}: let
  # Wrap ugrep/ug to always load the system-wide /etc/ugrep.conf
  ugrepWithConfig = pkgs.ugrep.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
    postInstall =
      (old.postInstall or "")
      + ''
        wrapProgram "$out/bin/ugrep" --add-flags "--config=/etc/ugrep.conf"
        wrapProgram "$out/bin/ug" --add-flags "--config=/etc/ugrep.conf"
      '';
  });
in {
  environment.systemPackages = [
    pkgs.ast-grep # AST-aware grep
    pkgs.ripgrep # better grep
    ugrepWithConfig # better grep, rg alternative (wrapped with global config)
  ];
}
