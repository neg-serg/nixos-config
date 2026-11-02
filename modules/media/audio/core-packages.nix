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
  # glm-usbmon-priv: root helper for USB traffic captures — mounts debugfs for
  # the length of one usbmon session and unmounts it on stop (invoked via
  # NOPASSWD sudo from the GLM/GNet protocol work).
  glmUsbmonPriv = pkgs.writeShellScriptBin "glm-usbmon-priv" (
    builtins.readFile ./core-packages/glm-usbmon-priv.sh
  );
in
{
  environment.systemPackages = lib.mkAfter [
    # -- Volume control --
    pkgs.genlc # Genelec SAM monitor volume control via GLM USB adapter
    glmUsbmonPriv # root helper (NOPASSWD) for usbmon captures of the GLM adapter

    # -- RME HDSPe --
    pkgs.hdspeconf # HDSPe matrix mixer & config (for snd-hdspe driver)
    pkgs.alsa-tools # hdspmixer, hdsploader (RME HDSPe userland tools)

    # -- Mixer --
    pkgs.hyprpwcenter # PipeWire control center — the session mixer (M4+C+p scratchpad)
  ];

  services.udev.extraRules = ''
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
  '';
}
