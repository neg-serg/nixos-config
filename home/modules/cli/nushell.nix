{
  lib,
  pkgs,
  ...
}: let
  # Path to the nushell config files in this repo
  nuConfDir = ./nushell-conf;

  # Generate aliae configuration for nushell
  aliaeContent = import ../../../lib/aliae.nix {
    inherit lib pkgs;
    isNushell = true;
  };
  aliaeConfig = pkgs.writeText "aliae.yaml" aliaeContent;

  # oh-my-posh theme config
  ompConfig = ../files/shell/zsh/neg.omp.json;

  # Generate the oh-my-posh init script at build time
  ompInitScript = pkgs.runCommand "omp-init-nu" {} ''
    ${pkgs.oh-my-posh}/bin/oh-my-posh init nu --config ${ompConfig} --print > $out 2>/dev/null || echo "# oh-my-posh init failed" > $out
  '';

  # Generate aliae init script at build time
  aliaeInitScript = pkgs.runCommand "aliae-init-nu" {} ''
    ${pkgs.aliae}/bin/aliae init nu --config ${aliaeConfig} --print > $out
  '';

  # Build the final config.nu with oh-my-posh init substituted
  finalConfigNu = pkgs.runCommand "nushell-config-nu" {} ''
    cp ${nuConfDir}/config.nu $out
    chmod +w $out
    substituteInPlace $out \
      --replace "source @OH_MY_POSH_INIT@" "source ${ompInitScript}"
  '';
in {
  programs.nushell = {
    enable = true;

    # Use the custom env.nu
    envFile.source = "${nuConfDir}/env.nu";

    # Use the patched config.nu
    configFile.source = finalConfigNu;
  };

  # Link additional nushell config files to XDG config
  xdg.configFile = {
    "nushell/aliases.nu".source = "${nuConfDir}/aliases.nu";
    "nushell/git.nu".source = "${nuConfDir}/git.nu";
    "nushell/broot.nu".source = "${nuConfDir}/broot.nu";
    "nushell/git-completion.nu".source = "${nuConfDir}/git-completion.nu";
    "nushell/aliae.nu".source = aliaeInitScript;
  };

  home.packages = [
    pkgs.carapace # completions for nushell
  ];
}
