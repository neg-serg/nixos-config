# lsfg-vk — Lossless Scaling Frame Generation on Linux
#
# Implicit Vulkan layer: the manifest in /etc/vulkan/implicit_layer.d makes the
# loader hook every Vulkan app; disable per-app with DISABLE_LSFGVK=1.
# Runtime requirement: own Lossless Scaling on Steam with the "lsfg-vk" branch
# checked out (provides lsfg-vk.dll, found under steamapps/common/...).
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
      builtins.replaceStrings [ "../../../lib/liblsfg-vk-layer.so" ] [ "${lsfg}/lib/liblsfg-vk-layer.so" ]
        (builtins.readFile "${lsfg}/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json");
  };
}
