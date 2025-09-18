{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.blktrace # block layer tracing tools
    pkgs.dmraid # old-style RAID config utility
    pkgs.exfat # exFAT libs
    pkgs.exfatprogs # exFAT utilities
    pkgs.fio # disk benchmark
    pkgs.gptfdisk # sgdisk and friends
    pkgs.ioping # IO latency measuring tool
    pkgs.mtools # MS-DOS disk utilities
    pkgs.multipath-tools # kpartx, etc. for images
    pkgs.nvme-cli # NVMe management tools
    pkgs.ostree # Git for OS binaries
    pkgs.parted # CLI disk manager
    pkgs.smartmontools # smartctl
  ];
}
