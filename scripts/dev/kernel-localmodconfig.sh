#!/usr/bin/env bash
# kernel-localmodconfig — Generate boot.kernelPatches.structuredExtraConfig from running system
#
# Usage:
#   scripts/dev/kernel-localmodconfig.sh [--only-loaded] [--candidates] [--help]
#
# Reads /proc/modules (loaded modules), /proc/config.gz (kernel .config),
# and /lib/modules/$(uname -r)/modules.builtin to produce a Nix expression
# suitable for boot.kernelPatches.[].structuredExtraConfig.
#
# Output:
#   - Loaded modules → CONFIG_* = yes   (with known or auto-converted names)
#   - Unloaded =m modules → CONFIG_* = no  (candidates for disabling)
#
# Options:
#   --only-loaded  Only emit loaded modules (skip =m → no candidates)
#   --candidates   Only emit the candidate-disabled section (no loaded = yes)
#   -h, --help     Show this help
#
# Requires: /proc/config.gz (common on NixOS), /proc/modules
#
# shellcheck disable=SC2207,SC2086
set -euo pipefail

# ────────────────────────────────────────────────────────────
# Constants
# ────────────────────────────────────────────────────────────
KVER="$(uname -r)"
SCRIPT_NAME="$(basename "$0")"
ONLY_LOADED=false
ONLY_CANDIDATES=false

for arg in "$@"; do
  case "$arg" in
    --only-loaded) ONLY_LOADED=true ;;
    --candidates) ONLY_CANDIDATES=true ;;
    -h|--help)
      sed -n '3,16p' "$0" | sed 's/^# //'
      exit 0
      ;;
  esac
done

# ────────────────────────────────────────────────────────────
# Known module → CONFIG_* mapping
#
# These are manually verified for this system (AMD X570, Navi21,
# RME HDSPe AIO Pro, etc.).  Add entries as you verify them.
# ────────────────────────────────────────────────────────────
declare -A MOD2CONFIG
# --- Graphics / DRM ---
MOD2CONFIG[amdgpu]="DRM_AMDGPU"
MOD2CONFIG[drm]="DRM"
MOD2CONFIG[drm_kms_helper]="DRM_KMS_HELPER"
MOD2CONFIG[drm_exec]="DRM_EXEC"
MOD2CONFIG[drm_suballoc_helper]="DRM_SUBALLOC_HELPER"
MOD2CONFIG[drm_buddy]="DRM_BUDDY"
MOD2CONFIG[drm_display_helper]="DRM_DISPLAY_HELPER"
MOD2CONFIG[drm_ttm_helper]="DRM_TTM_HELPER"
MOD2CONFIG[ttm]="DRM_TTM"
MOD2CONFIG[sch_fq]="NET_SCH_FQ"
MOD2CONFIG[sch_fq_codel]="NET_SCH_FQ_CODEL"
MOD2CONFIG[sch_pie]="NET_SCH_PIE"
# --- AMD PMF / Platform ---
MOD2CONFIG[amd_pmf]="AMD_PMF"
MOD2CONFIG[amd_pmc]="AMD_PMC"
MOD2CONFIG[amd_hsmp]="AMD_HSMP"
# --- Sensors / HWMON ---
MOD2CONFIG[nct6775]="SENSORS_NCT6775"
MOD2CONFIG[i2c_nct6775]="I2C_NCT6775"
MOD2CONFIG[k10temp]="SENSORS_K10TEMP"
MOD2CONFIG[asus_ec_sensors]="SENSORS_ASUS_EC"
MOD2CONFIG[ec_sys]="EC_SYS"
# --- I2C ---
MOD2CONFIG[i2c_dev]="I2C_CHARDEV"
MOD2CONFIG[i2c_piix4]="I2C_PIIX4"
MOD2CONFIG[i2c_nvidia_gpu]="I2C_NVIDIA_GPU"
MOD2CONFIG[i2c_designware_platform]="I2C_DESIGNWARE_PLATFORM"
# --- KVM / Virtualisation ---
MOD2CONFIG[kvm]="KVM"
MOD2CONFIG[kvm_amd]="KVM_AMD"
# --- Network / TCP ---
MOD2CONFIG[tcp_bbr]="TCP_CONG_BBR"
MOD2CONFIG[tcp_diag]="TCP_DIAG"
# --- NVMe ---
MOD2CONFIG[nvme]="NVME_CORE"
MOD2CONFIG[nvme_core]="NVME_CORE"
MOD2CONFIG[nvme_auth]="NVME_AUTH"
# --- USB ---
MOD2CONFIG[xhci_hcd]="USB_XHCI_HCD"
MOD2CONFIG[xhci_pci]="USB_XHCI_PCI"
MOD2CONFIG[usbhid]="USB_HID"
MOD2CONFIG[hid]="HID"
MOD2CONFIG[hid_generic]="HID_GENERIC"
MOD2CONFIG[hid_amd_sfh]="HID_AMD_SFH"
MOD2CONFIG[usbcore]="USB"
MOD2CONFIG[usb_common]="USB_COMMON"
MOD2CONFIG[ehci_hcd]="USB_EHCI_HCD"
MOD2CONFIG[ehci_pci]="USB_EHCI_PCI"
MOD2CONFIG[ohci_pci]="USB_OHCI_HCD"
# --- Audio ---
MOD2CONFIG[snd_usb_audio]="SND_USB_AUDIO"
MOD2CONFIG[snd_usbmidi_lib]="SND_USB_MIDI_LIB"
MOD2CONFIG[snd_hda_intel]="SND_HDA_INTEL"
MOD2CONFIG[snd_hda_codec]="SND_HDA_CODEC"
MOD2CONFIG[snd_hda_codec_hdmi]="SND_HDA_CODEC_HDMI"
MOD2CONFIG[snd_hda_core]="SND_HDA_CORE"
MOD2CONFIG[snd_pcm]="SND_PCM"
MOD2CONFIG[snd_timer]="SND_TIMER"
MOD2CONFIG[snd]="SND"
MOD2CONFIG[snd_rawmidi]="SND_RAWMIDI"
MOD2CONFIG[snd_seq]="SND_SEQUENCER"
MOD2CONFIG[snd_seq_device]="SND_SEQ_DEVICE"
MOD2CONFIG[snd_hwdep]="SND_HWDEP"
MOD2CONFIG[snd_compress]="SND_COMPRESS_OFFLOAD"
MOD2CONFIG[snd_hda_codec_realtek]="SND_HDA_CODEC_REALTEK"
MOD2CONFIG[snd_hda_codec_generic]="SND_HDA_CODEC_GENERIC"
# --- File Systems ---
MOD2CONFIG[ntfs3]="NTFS3_FS"
MOD2CONFIG[fuse]="FUSE_FS"
MOD2CONFIG[overlay]="OVERLAY_FS"
MOD2CONFIG[btrfs]="BTRFS_FS"
MOD2CONFIG[xfs]="XFS_FS"
MOD2CONFIG[zfs]="# OUT_OF_TREE (ZFS)"
MOD2CONFIG[spl]="# OUT_OF_TREE (SPL)"
MOD2CONFIG[zraid]="# OUT_OF_TREE (ZFS)"
# --- WireGuard / VPN ---
MOD2CONFIG[wireguard]="WIREGUARD"
MOD2CONFIG[amneziawg]="# OUT_OF_TREE (AmneziaWG)"
# --- NTSync ---
MOD2CONFIG[ntsync]="# OUT_OF_TREE (ntsync — proton)"
# --- v4l2 / Video ---
MOD2CONFIG[v4l2loopback]="# OUT_OF_TREE (v4l2loopback-dkms)"
MOD2CONFIG[videodev]="VIDEO_DEV"
MOD2CONFIG[video]="VIDEO"
MOD2CONFIG[uvcvideo]="USB_VIDEO_CLASS"
# --- GPU / Compute ---
MOD2CONFIG[hid_nvidia]="# OUT_OF_TREE (nvidia-kmod)"
# --- Extra hardware ---
MOD2CONFIG[sp5100_tco]="SP5100_TCO"
MOD2CONFIG[wmi]="ACPI_WMI"
MOD2CONFIG[wmi_bmof]="WMI_BMOF"
MOD2CONFIG[ccp]="CRYPTO_DEV_CCP"
MOD2CONFIG[mac_hid]="MAC_EMUMOUSEBTN"
MOD2CONFIG[gpio_amdpt]="GPIO_AMD_PT"
MOD2CONFIG[gpio_generic]="GPIO_GENERIC"
MOD2CONFIG[ledtrig_audio]="LEDS_TRIGGER_AUDIO"
MOD2CONFIG[acpi_cpufreq]="X86_ACPI_CPUFREQ"
MOD2CONFIG[it87]="SENSORS_IT87"
MOD2CONFIG[ee1004]="EE1004"  # SPD EEPROM (RAM info)
# --- Sound DSP (RME HDSPe AIO Pro via DKMS) ---
MOD2CONFIG[snd_hdspe]="# OUT_OF_TREE (rme-hdspe-dkms)"
MOD2CONFIG[snd_hdspm]="# OUT_OF_TREE (conflicts with snd-hdspe)"

# Auto-convert a module name to a CONFIG_* name by uppercasing and
# replacing hyphens with underscores.
auto_convert() {
  local mod="$1"
  echo "$mod" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

# ────────────────────────────────────────────────────────────
# Gather data
# ────────────────────────────────────────────────────────────

# Loaded modules — first column of /proc/modules
LOADED_MODS=()
while read -r mod rest; do
  LOADED_MODS+=("$mod")
done < /proc/modules
readonly LOADED_MODS

# Build a set for O(1) lookup
declare -A IS_LOADED
for m in "${LOADED_MODS[@]}"; do
  IS_LOADED["$m"]=1
done

# Built-in modules (compiled into the kernel image, not loadable)
BUILTIN_MODS=()
if [ -f "/lib/modules/${KVER}/modules.builtin" ]; then
  while IFS= read -r line; do
    # Strip .ko suffix and path, keep basename
    b="$(basename "$line" .ko)"
    BUILTIN_MODS+=("$b")
  done < "/lib/modules/${KVER}/modules.builtin"
fi
readonly BUILTIN_MODS

declare -A IS_BUILTIN
for m in "${BUILTIN_MODS[@]}"; do
  IS_BUILTIN["$m"]=1
done

# Available kernel .config (from /proc/config.gz)
KCONFIG_OPTS_M=()
KCONFIG_OPTS_Y=()
if [ -f /proc/config.gz ]; then
  while IFS='=' read -r name val; do
    case "$val" in
      m) KCONFIG_OPTS_M+=("$name") ;;
      y) KCONFIG_OPTS_Y+=("$name") ;;
    esac
  done < <(zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_' || true)

  # Also capture 'is not set' lines
  KCONFIG_OPTS_N=($(zcat /proc/config.gz 2>/dev/null | grep 'is not set' | sed 's/# \(CONFIG_[^ ]*\) is not set/\1/' || true))
fi

readonly KCONFIG_OPTS_M KCONFIG_OPTS_Y KCONFIG_OPTS_N

# Build a set of known CONFIG names from the running config
declare -A CONFIG_IS_Y CONFIG_IS_M
for c in "${KCONFIG_OPTS_Y[@]}"; do CONFIG_IS_Y["${c#CONFIG_}"]=1; done
for c in "${KCONFIG_OPTS_M[@]}"; do CONFIG_IS_M["${c#CONFIG_}"]=1; done

# ────────────────────────────────────────────────────────────
# Emit Nix expression
# ────────────────────────────────────────────────────────────

# Helper: look up or auto-convert a module name
resolve_config() {
  local mod="$1"
  local config="${MOD2CONFIG[$mod]:-}"
  if [ -n "$config" ]; then
    echo "$config"
  else
    auto_convert "$mod"
  fi
}

emit_preamble() {
  cat <<PREAMBLE
# Generated by ${SCRIPT_NAME} on $(date)
# Kernel: ${KVER}
#
# Usage: include in your NixOS config as:
#
#   boot.kernelPatches = [
#     {
#       name = "localmodconfig-${KVER//./-}";
#       patch = null;
#       structuredExtraConfig = with lib.kernel; {
#         …paste below…
#       };
#     }
#   ];
#
# NOTE:
#   - Entries marked # UNVERIFIED are auto-converted from module names.
#     Verify against \`/proc/config.gz\` or kernel source before using.
#   - Entries marked # OUT_OF_TREE are third-party modules (ZFS, nvidia,
#     ntsync, etc.) and do NOT have a kernel CONFIG option — they are
#     listed as comments only.
#   - Modules built into the kernel (modules.builtin) are always available;
#     they do not need structuredExtraConfig entries.
#
PREAMBLE
}

emit_loaded_section() {
  echo ""
  echo "  # === Loaded modules  (CONFIG_* = yes) ==="

  for mod in "${LOADED_MODS[@]}"; do
    local config
    config="$(resolve_config "$mod")"

    if [[ "$config" == "#"* ]]; then
      # Out-of-tree or special — comment only
      echo "      # ${config#\# } — loaded but no CONFIG option to set"
      continue
    fi

    local annotation="# loaded: ${mod}"
    if [ -z "${MOD2CONFIG[$mod]:-}" ]; then
      annotation+="  (UNVERIFIED)"
    fi

    # Cross-reference with /proc/config.gz if available
    if [ ${#KCONFIG_OPTS_M[@]} -gt 0 ] || [ ${#KCONFIG_OPTS_Y[@]} -gt 0 ]; then
      if [ -n "${CONFIG_IS_M[$config]:-}" ] || [ -n "${CONFIG_IS_Y[$config]:-}" ]; then
        echo "      ${config} = yes;  ${annotation}"
      else
        echo "      ${config} = yes;  ${annotation} — NOT FOUND in current .config"
      fi
    else
      echo "      ${config} = yes;  ${annotation}"
    fi
  done
}

emit_candidates_section() {
  echo ""
  echo "  # === Unloaded =m modules (CONFIG_* = no) ==="
  echo "  # These are built as loadable modules in the current kernel config"
  echo "  # but are NOT currently loaded.  Review and uncomment to disable."

  local count=0 total_checked=0 skipped_loaded=0 skipped_builtin=0 skipped_oot=0
  for config in "${KCONFIG_OPTS_M[@]}"; do
    total_checked=$((total_checked + 1))

    # Strip CONFIG_ prefix, lowercase — module names use underscores
    local stripped="${config#CONFIG_}"
    local guessed_mod
    guessed_mod="$(echo "$stripped" | tr '[:upper:]' '[:lower:]')"

    # Skip if the module is currently loaded
    if [ -n "${IS_LOADED[$guessed_mod]:-}" ]; then
      skipped_loaded=$((skipped_loaded + 1))
      continue
    fi

    # Skip if the module is built-in
    if [ -n "${IS_BUILTIN[$guessed_mod]:-}" ]; then
      skipped_builtin=$((skipped_builtin + 1))
      continue
    fi

    # Skip known out-of-tree modules (listed in our mapping)
    local mapped="${MOD2CONFIG[$guessed_mod]:-}"
    if [[ "$mapped" == "#"* ]]; then
      skipped_oot=$((skipped_oot + 1))
      continue
    fi

    # Limit output volume: only first 100 candidates to avoid overwhelming
    if [ "$count" -lt 100 ]; then
      echo "      # ${config} = no;  # guessed module: ${guessed_mod}"
    elif [ "$count" -eq 100 ]; then
      echo "      # ... ($(( ${#KCONFIG_OPTS_M[@]} )) total =m options, showing first 100 candidates)"
    fi
    count=$((count + 1))
  done

  echo "      # (checked ${total_checked} =m options: ${skipped_loaded} loaded, ${skipped_builtin} built-in, ${skipped_oot} out-of-tree, ${count} candidates)"
  if [ "$count" -eq 0 ]; then
    echo "      # (none — all =m modules appear to be loaded or built-in)"
  fi
}

emit_builtin_note() {
  echo ""
  echo "  # === Built-in modules ==="
  echo "  # These are compiled into the kernel image and are always present."
  echo "  # No structuredExtraConfig entries needed."
  echo "  # Count: ${#BUILTIN_MODS[@]} modules built into kernel"
}

# ────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────

emit_preamble

echo "{ lib, config, ... }: {"
echo "  boot.kernelPatches = [{"
echo "    name = \"localmodconfig-${KVER}\";"
echo "    patch = null;"
echo "    structuredExtraConfig = with lib.kernel; {"

if ! $ONLY_CANDIDATES; then
  emit_loaded_section
fi

if ! $ONLY_LOADED; then
  emit_candidates_section
fi

emit_builtin_note

# Summary stats
echo ""
echo "      # ── Summary ──"
echo "      # Loaded modules          : ${#LOADED_MODS[@]}"
if [ -f /proc/config.gz ]; then
  echo "      # Config =y (built-in)     : ${#KCONFIG_OPTS_Y[@]}"
  echo "      # Config =m (modules)      : ${#KCONFIG_OPTS_M[@]}"
  echo "      # Config =n (disabled)     : ${#KCONFIG_OPTS_N[@]}"
fi
echo "      # Built-in kernel modules: ${#BUILTIN_MODS[@]}"

# Close the Nix expression — note the double-close because we opened
# with {, boot.kernelPatches = [{, structuredExtraConfig = {.
echo "    };"
echo "  }];"
echo "}"
