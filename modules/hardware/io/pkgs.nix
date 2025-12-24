{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.blktrace # block layer tracing tools
    pkgs.dmraid # device mapper RAID tool for "fakeRAID" controllers
    pkgs.exfat # user-space implementation of the exFAT filesystem
    pkgs.exfatprogs # userspace utilities for exFAT filesystems
    pkgs.fio # flexible I/O tester for benchmarking and verification
    pkgs.gptfdisk # text-mode partitioning tools (gdisk, sgdisk, fixparts)
    pkgs.ioping # simple disk I/O latency monitoring tool
    pkgs.mtools # utilities to access MS-DOS disks from Unix
    pkgs.multipath-tools # tools for managing multi-path devices (includes kpartx)
    pkgs.nvme-cli # NVM-Express user space tooling
    pkgs.ostree # library and tool for content-addressed storage of OS binaries
    pkgs.parted # GNU Partition Editor
    pkgs.smartmontools # tools for monitoring S.M.A.R.T. data (smartctl, smartd)
  ];
}
