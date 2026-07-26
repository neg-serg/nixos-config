##
# Module: user/nix-maid/apps/supercollider
# Purpose: TidalCycles one-click launch.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  installQuark = pkgs.runCommand "install-superdirt-quark" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin
    cat > $out/bin/install-superdirt-quark << 'SCRIPT'
    #!/bin/sh
    set -eu
    echo "Installing SuperDirt quark (one-time)..."
    ${pkgs.supercollider}/bin/sclang << 'EOF'
    try { Quarks.install("https://codeberg.org/musikinformatik/SuperDirt"); "OK".postln; } { |err| ("FAIL: " ++ err.what).postln; }; 0.exit;
    EOF
    SCRIPT
    chmod +x $out/bin/install-superdirt-quark
  '';

  superdirtStartup = ''
    s.options.numBuffers = 1024 * 1024;
    s.options.memSize = 8192 * 64;
    s.options.numWireBufs = 256;
    s.options.maxNodes = 1024 * 64;
    s.options.numOutputBusChannels = 2;
    s.options.numInputBusChannels = 2;
    s.waitForBoot { "Server ready — SuperDirt loading...".postln; };
  '';

  bootNoop = ''
    s.options.numOutputBusChannels = 2;
    s.waitForBoot { "SC server ready".postln; };
  '';

  bootTidal = ''
    :set -fno-warn-orphans -Wno-type-defaults -XMultiParamTypeClasses -XOverloadedStrings
    :set prompt ""
    import Sound.Tidal.Boot
    default (Rational, Integer, Double, Pattern String)
    tidalInst <- mkTidal
    instance Tidally where tidal = tidalInst
    :set prompt "tidal> "
    :set prompt-cont ""
  '';
in
{
  config = lib.mkIf enabled {
    environment.sessionVariables.LD_LIBRARY_PATH =
      [ "${pkgs.pipewire.jack}/lib" ];
    environment.systemPackages = [ installQuark ];
    environment.etc = {
      "skel/.config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      "skel/.config/SuperCollider/boot_noop.scd".text = bootNoop;
    };
    users.users.neg.maid.file.home = {
      ".config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      ".config/SuperCollider/boot_noop.scd".text = bootNoop;
      ".config/tidal/BootTidal.hs".text = bootTidal;
      ".local/share/SuperCollider/downloaded-quarks/Dirt-Samples".source =
        "${pkgs.neg.dirt-samples}/share/Dirt-Samples";
    };
  };
}
