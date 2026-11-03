{ pkgs, ... }:
# Firmware subset for trantor: AMD GPUs (Navi 48 + Granite Ridge iGPU),
# MediaTek MT7927 Wi-Fi/Bluetooth, Realtek RTL8126 Ethernet and the wireless
# regulatory database. Everything else in linux-firmware (Intel/Qualcomm/
# NVIDIA/Mellanox/...) is for hardware this host does not have.
#
# Keep amdgpu/ and mediatek/ whole: both drivers request many per-generation
# files and a future kernel bump may ask for another one. rtl_nic is tiny.
# The MT6639 Bluetooth blob is added separately by the host (firmwareBlob).
pkgs.runCommand "linux-firmware-minimal" { } ''
  mkdir -p $out/lib/firmware
  for dir in amdgpu mediatek rtl_nic; do
    cp -rL ${pkgs.linux-firmware}/lib/firmware/$dir $out/lib/firmware/
  done
  for file in regulatory.db regulatory.db.p7s WHENCE LICENSE LICENCE README; do
    if [ -e ${pkgs.linux-firmware}/lib/firmware/$file ]; then
      cp -L ${pkgs.linux-firmware}/lib/firmware/$file $out/lib/firmware/
    fi
  done
''
