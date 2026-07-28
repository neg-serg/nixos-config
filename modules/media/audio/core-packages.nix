##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of user profile state.
# Trigger: always enabled (was gated behind roles.workstation which is always true on the only host).
{
  lib,
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.mkAfter [
    # -- Volume control --
    pkgs.genlc # Genelec SAM monitor volume control via GLM USB adapter
    pkgs.pw-volume # minimal PipeWire volume controller for scripts

    # -- RME HDSPe --
    pkgs.hdspeconf # HDSPe matrix mixer & config (for snd-hdspe driver)
    pkgs.alsa-tools # hdspmixer, hdsploader (RME HDSPe userland tools)

    # -- GUI Patchbays --
    pkgs.coppwr # PipeWire CLI to copy/paste complex graphs
    pkgs.pwvucontrol # Qt6 PipeWire volume control (pavucontrol alternative, no GTK)
  ];

  services.udev.extraRules = ''
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
  '';
}
