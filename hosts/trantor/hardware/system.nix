# Literal host-system data for host 'trantor', kept out of the module body so
# hardware.nix stays wiring: stable NIC link names, the kexec helper scripts
# and the out-of-tree MT6639 Bluetooth firmware blob.
# Comments travel with the data — they document the hardware quirks.
{
  pkgs,
  config,
}:
{
  # Create the NERV firmware boot entry that boot.loader.nerv's own install step
  # would add. Kept here because /boot is a systemd automount on this host:
  # `findmnt --target /boot` then prints two rows (the autofs and the real
  # device), and the module's snippet feeds that two-line value into lsblk,
  # which fails and aborts the whole bootloader install under `set -e`. This
  # variant takes the last row, and every failure path only prints the manual
  # efibootmgr command instead of breaking activation.
  nervEfiEntry = pkgs.writeShellApplication {
    name = "nerv-efi-entry";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.efibootmgr
      pkgs.gnugrep
      pkgs.util-linux
    ];
    text = ''
      esp=/boot
      loader='\EFI\nerv\nerv-boot.efi'

      # No EFI variables to write — nothing to do.
      [ -d /sys/firmware/efi/efivars ] || exit 0

      # An entry pointing at nerv-boot already exists (ours or the user's):
      # leave it and its boot order alone.
      if efibootmgr -v | grep -qiF "$loader"; then
        exit 0
      fi

      # tail -n1 skips the autofs row; mountinfo lists the real mount last.
      src="$(findmnt -nro SOURCE --target "$esp" 2>/dev/null | tail -n1 || true)"
      case "$src" in
        /dev/*) ;;
        *)
          echo "nerv: cannot resolve the ESP device ($src); create the entry by hand" >&2
          exit 0
          ;;
      esac
      disk="$(lsblk -nro PKNAME "$src" 2>/dev/null || true)"
      part="$(lsblk -nro PARTN "$src" 2>/dev/null || true)"
      if [ -z "$disk" ] || [ -z "$part" ]; then
        echo "nerv: cannot derive disk/partition for $src; create the entry by hand:" >&2
        echo "nerv:   efibootmgr --create --disk <disk> --part <part> --label NERV --loader '$loader'" >&2
        exit 0
      fi
      if efibootmgr --quiet --create --disk "/dev/$disk" --part "$part" --label NERV --loader "$loader"; then
        echo "nerv: created firmware boot entry NERV (first in BootOrder)"
      else
        echo "nerv: efibootmgr failed; create the entry by hand (see nerv-boot's README)" >&2
      fi
    '';
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

  # No MT7927 ASPM quirk here. The out-of-tree mt7927 module needed L1 off to
  # keep the card on the bus, but the in-tree mt7925e does not: L1 is already
  # disabled for every link by "pcie_aspm=off" (hardware/kernel.nix), and with
  # ASPM disabled the kernel creates no link/* attributes at all — all
  # /sys/bus/pci/devices/*/link/ are empty — so the old udev rule had nothing
  # to write (it also matched 0x7927 while the card enumerates as 14c3:6639).
  # Keep in mind that this file is data only: named attrs are read by
  # hardware.nix, and a `services.udev` block here would be merged into nothing.

  # mt7925e hands the chip to two firmware low-power states, and waking from
  # them is the path that ends in "driver own failed" and a card that drops off
  # the bus. Both are debugfs knobs of the driver itself: `runtime-pm` (doze)
  # stores pm->enable_user, `deep-sleep` stores pm->ds_enable_user; 0 pins the
  # chip awake, which is free on a desktop PSU.
  #
  # Verified against the kernel this host builds (7.3.1): the files are created
  # by mt7925_init_debugfs() right after the wiphy registers —
  # drivers/net/wireless/mediatek/mt76/mt7925/debugfs.c:308,314, mode 0600, at
  # /sys/kernel/debug/ieee80211/<wiphy>/mt76/ (cfg80211 creates the parent
  # unconditionally, core.c:2083). CONFIG_MT7925E=m and CONFIG_DEBUG_FS=y, and
  # the built mt7925-common.ko carries the names, so the code is not compiled
  # out. MAC80211_DEBUGFS is off and irrelevant here: that gate covers
  # mac80211's own per-phy files, not mt76's directory.
  #
  # The values live in driver memory, so they survive until the module is
  # unloaded — one write per probe is enough. The systemd unit that runs this
  # lives in hardware.nix: this file is plain data (see the header), so a
  # `systemd.services` block here would be merged into nothing.
  mt7925PmOff = pkgs.writeShellApplication {
    name = "mt7925-disable-pm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      shopt -s nullglob

      # The netdev appears a few lines before the debugfs dirs do: mt7925_init()
      # calls mt76_register_device() first and mt7925_init_debugfs() after it.
      for _ in {1..50}; do
        dirs=(/sys/kernel/debug/ieee80211/phy*/mt76)
        [ "''${#dirs[@]}" -gt 0 ] && break
        sleep 0.2
      done

      if [ "''${#dirs[@]}" -eq 0 ]; then
        # No phy at all is a card that probe has not reached yet, and the device
        # unit retries then; a phy without mt76 means the driver bound but its
        # debugfs never appeared — that is worth a failed unit.
        phys=(/sys/class/ieee80211/phy*)
        if [ "''${#phys[@]}" -gt 0 ]; then
          echo "mt7925-disable-pm: phy exists but no mt76 debugfs dir" >&2
          exit 1
        fi
        echo "mt7925-disable-pm: no mt7925e phy yet, nothing to pin" >&2
        exit 0
      fi

      for dir in "''${dirs[@]}"; do
        echo 0 > "$dir/deep-sleep"
        echo 0 > "$dir/runtime-pm"
        echo "mt7925-disable-pm: $dir runtime-pm=$(cat "$dir/runtime-pm") deep-sleep=$(cat "$dir/deep-sleep")"
      done
    '';
  };
}
