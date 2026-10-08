# Literal host-system data for host 'trantor', kept out of the module body so
# hardware.nix stays wiring: bootloader style, stable NIC link names, the
# kexec helper scripts and the out-of-tree MT6639 Bluetooth firmware blob.
# Comments travel with the data — they document the hardware quirks.
{
  pkgs,
  config,
}:
{
  # Limine bootloader theme
  limineStyle = {
    interface = {
      branding = "NixOS";
      brandingColor = "00D9FF";
      # Match autoboot countdown colour to the branding accent
      helpColor = "00AAAA";
      helpColorBright = "55FF55";
    };
    # No wallpaper image — an explicit empty list overrides the nixpkgs default
    # (nixos-artwork simple-dark-gray); the loader draws on the backdrop below.
    wallpapers = [ ];
    backdrop = "000000";
  };

  # Rename NICs to stable names via systemd-networkd link files
  networkLinks = {
    "10-net0" = {
      matchConfig.MACAddress = "a0:ad:9f:7e:4b:4e";
      linkConfig.Name = "net0";
    };
    "10-net1" = {
      matchConfig.MACAddress = "a0:ad:9f:7e:4b:4f";
      linkConfig.Name = "net1";
    };
  };

  # Export non-root ZFS pools before kexec so the new kernel imports
  # them cleanly (without -f). Skip pools that still have mounted
  # datasets (common for gamez during gameplay).
  kexecPrepareZfs = pkgs.writeShellScript "kexec-prepare-zfs" ''
    for pool in gamez zero; do
      if zpool status "$pool" >/dev/null 2>&1; then
        mounted="$(zfs list -H -o mounted "$pool" 2>/dev/null | grep -c yes || true)"
        if [ "$mounted" -eq 0 ]; then
          zpool export "$pool" 2>/dev/null || true
        fi
      fi
    done
  '';

  # Unbind discrete GPU (Radeon RX 9070 XT, Navi 48) from amdgpu
  # before kexec to force clean re-initialisation in the new kernel.
  # Without this, amdgpu may fail to reset GPU firmware/VRAM state
  # on kexec, causing lockup during initrd module load.
  kexecPrepareGpu = pkgs.writeShellScript "kexec-prepare-gpu" ''
    for slot in 0000:03:00.0 0000:7c:00.0; do
      path="/sys/bus/pci/drivers/amdgpu/$slot"
      if [ -e "$path" ]; then
        echo "$slot" > /sys/bus/pci/drivers/amdgpu/unbind 2>/dev/null || true
      fi
    done
  '';

  kexecRebuild = pkgs.writeShellScriptBin "kexec-rebuild" ''
    set -eu
    # Atomically rebuild the system and kexec into the new generation.
    # Passes any extra arguments (e.g. --flake, --use-remote-sudo) through.
    if [ "$${EUID:-}" -ne 0 ] && [ "$${UID:-}" -ne 0 ]; then
      echo "kexec-rebuild: must be run as root" >&2
      exit 1
    fi
    echo "=== Rebuilding NixOS ==="
    nixos-rebuild switch "$@"
    echo "=== kexec'ing into new generation ==="
    systemctl kexec
  '';

  # MediaTek MT6639/MT7927 BT RAM code — not in linux-firmware yet (only
  # WiFi blobs are); needed by the backported btmtk driver (btmtk_fw_get_filename
  # requests mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin for dev_id 0x6639).
  # Blob extracted from ASUS driver DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R
  # (mtkwlan.dat) via jetm/mediatek-mt7927-dkms extract_firmware.py; sha256
  # 669c5c99a0c59c85c1285d3d1b8b31915c2d31341a2244f4eddcbfd60ffbbc76.
  # compressFirmware = false: the xz-compress wrapper (compressFirmwareXz)
  # renames single-file packages with a hash prefix, which trips Nix's
  # "output not allowed to refer" check; plain blob is found fine by the
  # firmware loader.
  firmwareBlob = pkgs.runCommand "mt6639-bt-firmware" { compressFirmware = false; } ''
    mkdir -p $out/lib/firmware/mediatek/mt7927
    # Explicit dest name: the imported store path keeps a hash prefix in its
    # basename, but the driver requests the plain filename.
    cp ${config.lib.neg.path "files/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"} \
      $out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
  '';
}
