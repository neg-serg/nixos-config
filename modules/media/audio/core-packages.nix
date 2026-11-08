##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of user profile state.
# Trigger: always enabled.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  # The HDSPe matrix mixer is a GUI (wxWidgets + WebKit, 214.7 MiB exclusive)
  # opened by hand when routing changes, so it is built on first use.
  onDemand = config.lib.neg.onDemand pkgs;

  # glm-usbmon-priv: root helper for USB traffic captures — mounts debugfs for
  # the length of one usbmon session and unmounts it on stop (invoked via
  # NOPASSWD sudo from the GLM/GNet protocol work).
  glmUsbmonPriv = pkgs.writeShellScriptBin "glm-usbmon-priv" (
    builtins.readFile ./core-packages/glm-usbmon-priv.sh
  );

  # Only the HDSPe mixer and control panel are wanted here. The full alsa-tools
  # set drags GTK4/GStreamer/dev outputs into the closure (1.4 GiB total; 57 MiB
  # of it gtk4-dev referenced from the package's own binaries) for utilities
  # this host never runs. hdsploader goes too: it is the *old* HDSP PCI firmware
  # loader (multiface/digiface), while this host runs an HDSPe AIO Pro whose
  # firmware the kernel module handles; and its binary hardcodes absolute
  # firmware paths inside the original package.
  #
  # `strip --strip-debug` drops the DWARF build paths, `patchelf --shrink-rpath`
  # drops the RPATH entry pointing at alsa-tools/lib. Both were store references
  # to the original package, which is what kept its dev outputs in the closure.
  alsaToolsHdsp = pkgs.runCommand "alsa-tools-hdsp" { } ''
    for b in hdspmixer hdspconf; do
      install -Dm755 ${pkgs.alsa-tools}/bin/$b $out/bin/$b
      ${pkgs.binutils}/bin/strip --strip-debug $out/bin/$b
      ${pkgs.patchelf}/bin/patchelf --shrink-rpath $out/bin/$b
    done
  '';
in
{
  environment.systemPackages = lib.mkAfter [
    # -- Volume control --
    pkgs.genlc # Genelec SAM monitor volume control via GLM USB adapter
    glmUsbmonPriv # root helper (NOPASSWD) for usbmon captures of the GLM adapter

    # -- RME HDSPe --
    (onDemand {
      name = "hdspeconf";
      attr = "hdspeconf";
    }) # HDSPe matrix mixer & config (snd-hdspe driver), built on first use
    alsaToolsHdsp # hdspmixer, hdspconf (RME HDSPe userland tools)

    # -- Mixer --
    pkgs.hyprpwcenter # PipeWire control center — the session mixer (M4+C+p scratchpad)
  ];

  services.udev.extraRules = ''
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
  '';
}
