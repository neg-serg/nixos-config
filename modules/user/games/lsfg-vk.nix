# lsfg-vk — Lossless Scaling Frame Generation on Linux
#
# Implicit Vulkan layer: the manifest in /etc/vulkan/implicit_layer.d makes the
# loader hook every Vulkan app; disable per-app with DISABLE_LSFGVK=1.
# Runtime requirement: own Lossless Scaling on Steam with the "lsfg-vk" branch
# checked out (provides lsfg-vk.dll, found under steamapps/common/...).
#
# Known state of the vendored 2.0.0-rc1 prebuilt (measured 2026-10-19, Vulkan loader
# 1.4.357): the layer declines interface negotiation - its own global init throws and it
# returns VK_ERROR_INITIALIZATION_FAILED - so the loader logs
#   "Failed to find 'vkGetInstanceProcAddr' in layer .../liblsfg-vk-layer.so"
# and skips the layer. Frame generation is inactive, and every Vulkan app on the host pays
# two loader ERROR lines. The layer never exported vkGetInstanceProcAddr (the pristine
# upstream tarball shows the same, so it is not a patchelf artefact). Re-check with
#   VK_LOADER_DEBUG=error vulkaninfo --summary 2>&1 | rg lsfg
# and silence it by dropping this manifest or bumping the prebuilt, not by disabling all
# Vulkan layers.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.profiles.games or { };
  lsfg = pkgs.neg.lsfg-vk;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ lsfg ]; # lsfg-vk-cli + lsfg-vk-ui (Qt6)

    # Implicit layer manifest → Vulkan loader picks it up for every app.
    # The shipped manifest's relative library_path only works inside the
    # package layout, so rewrite it to the absolute store path.
    environment.etc."vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json".text =
      # A string inside the shipped manifest, not a Nix path: it is the
      # package's own relative library_path being rewritten.
      # allow-relative: the string is the upstream value, kept verbatim.
      builtins.replaceStrings [ "../../../lib/liblsfg-vk-layer.so" ] [ "${lsfg}/lib/liblsfg-vk-layer.so" ]
        (builtins.readFile "${lsfg}/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json");
  };
}
