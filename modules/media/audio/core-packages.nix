##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of user profile state.
# Trigger: always enabled.
{
  lib,
  pkgs,
  ...
}:
let
  # glm-adapter-priv: root helper that binds/unbinds the GLM adapter's usbhid
  # interface so the adapter can move between the host and the dockur VM
  # (invoked via NOPASSWD sudo from ~/.local/bin/glm-adapter).
  glmAdapterPriv = pkgs.writeShellScriptBin "glm-adapter-priv" (
    builtins.readFile ./core-packages/glm-adapter-priv.sh
  );
in
{
  environment.systemPackages = lib.mkAfter [
    # -- Volume control --
    pkgs.genlc # Genelec SAM monitor volume control via GLM USB adapter
    glmAdapterPriv # root helper (NOPASSWD) that moves the GLM adapter host<->VM
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
