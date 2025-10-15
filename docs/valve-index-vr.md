# Valve Index VR on Hyprland (AMD Radeon RX 7900 XTX)

## Rebuild and enable services
- Run `sudo nixos-rebuild switch --flake /etc/nixos#telfir` to apply the new VR stack.
- Reboot once so the kernel parameters, udev rules, and user services pick up cleanly.

## SteamVR sanity tests
- Launch Steam and install the SteamVR package (if not already present).
- In SteamVR settings → Developer → Set Current OpenXR Runtime, set it to “SteamVR”.
- Start SteamVR; confirm the compositor opens and shows the home space without error popups.

## Optional diagnostics
- Run `openxr-info` (from `vulkan-tools`) to dump runtime information.
- Execute `vkcube` and `vkcube --display` to validate Vulkan acceleration on both native and X11 fallback paths.
- For controller mappings, check `~/.local/share/Steam/config/steamvr.vrsettings` after pairing to ensure input profiles loaded.
