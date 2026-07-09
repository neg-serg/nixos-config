##
# Module: system/kernel/minimize
# Purpose: Aggressively disable ~200+ kernel subsystems not needed on this
#          desktop/gaming system (odin — AMD 9950X3D, NVMe-only, ZFS root).
#
# Strategy: Use boot.kernelPatches with structuredExtraConfig to force
# CONFIG_*=n for unused features while keeping essentials at =y.
#
# Must‑KEEP items verified against modules/system/filesystems.nix,
# modules/system/kernel/params.nix, and hardware config.
#
# NOTE about out‑of‑tree modules: ZFS, amneziawg, v4l2loopback, ntsync,
# tcp_bbr are NOT set here — they are handled by the kernel package build
# and/or extraModulePackages, not by structuredExtraConfig.
{
  lib,
  config,
  ...
}: {
  boot.kernelPatches = [
    {
      name = "kernel-minimize";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        # ====================================================================
        # ESSENTIAL FEATURES (must-keep, verified from codebase)
        # ====================================================================
        DRM_AMDGPU = yes;         # AMD Radeon GPU
        I2C = yes;                # I2C subsystem — i2c-dev for OpenRGB
        HWMON = yes;              # Hardware monitoring — nct6775 for fan control
        SND_USB = yes;            # USB audio interface
        NVME_CORE = yes;          # NVMe core
        NVME = yes;               # NVMe PCIe driver — 3x Samsung drives
        BLUETOOTH = yes;          # Bluetooth subsystem — game controller support
        INPUT_JOYSTICK = yes;     # Joystick/game controller support
        KVM = yes;                # KVM core — kvm-amd loaded
        KVM_AMD = yes;            # AMD virtualization support
        USB_SUPPORT = yes;        # USB subsystem
        USB = yes;                # USB driver
        XFS_FS = yes;             # XFS — in boot.supportedFilesystems
        EXT4_FS = yes;            # EXT4 — needed by containers
        VFAT_FS = yes;            # vfat — EFI boot partition
        EXFAT_FS = yes;           # exFAT — in boot.supportedFilesystems
        UDF_FS = yes;             # UDF — in boot.supportedFilesystems

        # ====================================================================
        # DEBUG / TRACE / PROFILING
        # ====================================================================
        DEBUG_FS = no;
        DEBUG_KERNEL = no;
        DEBUG_INFO = no;
        DEBUG_MISC = no;
        DYNAMIC_DEBUG = no;
        FTRACE = no;
        FUNCTION_TRACER = no;
        STACK_TRACER = no;
        TRACING = no;
        TRACE_EVENTS = no;
        TRACEPOINTS = no;
        PROBE_EVENTS = no;
        KPROBES = no;
        UPROBES = no;
        PERF_EVENTS = no;
        LOCKDEP = no;
        LOCK_STAT = no;
        DEBUG_OBJECTS = no;
        DEBUG_PAGEALLOC = no;
        DEBUG_LIST = no;
        DEBUG_SG = no;
        DEBUG_NOTIFIERS = no;
        DEBUG_CREDENTIALS = no;
        DEBUG_PLIST = no;
        DEBUG_VM = no;
        DEBUG_SPINLOCK = no;
        DEBUG_MUTEXES = no;
        DEBUG_ATOMIC_SLEEP = no;
        DEBUG_BUGVERBOSE = no;
        DEBUG_ENTERPRISE = no;
        PM_DEBUG = no;
        PM_ADVANCED_DEBUG = no;
        ACPI_DEBUG = no;

        # ====================================================================
        # UNUSED NETWORK PROTOCOLS
        # ====================================================================
        IP_DCCP = no;
        IP_SCTP = no;
        ATM = no;
        L2TP = no;
        DECNET = no;
        IPX = no;
        APPLETALK = no;
        AX25 = no;
        NETROM = no;
        ROSE = no;
        TIPC = no;
        IRDA = no;
        NFC = no;
        CAN = no;

        # ====================================================================
        # UNUSED NETWORK FILESYSTEM CLIENTS (userspace handles these)
        # ====================================================================
        CEPH_FS = no;
        SMBFS = no;
        CIFS = no;
        NFS_FS = no;
        NFSD = no;

        # ====================================================================
        # UNUSED FILESYSTEMS
        # ====================================================================
        EXT2_FS = no;             # EXT4 handles ext2/3
        EXT3_FS = no;
        REISERFS_FS = no;
        JFS_FS = no;
        OCFS2_FS = no;
        BTRFS_FS = no;
        F2FS_FS = no;
        NILFS2_FS = no;
        GFS2_FS = no;
        HFS_FS = no;
        HFSPLUS_FS = no;
        BEFS_FS = no;
        ADFS_FS = no;
        AFFS_FS = no;
        EFS_FS = no;
        JFFS2_FS = no;
        CRAMFS = no;
        SQUASHFS = no;
        VXFS_FS = no;
        QNX4FS_FS = no;
        QNX6FS_FS = no;
        SYSV_FS = no;
        UFS_FS = no;
        EROFS_FS = no;
        ORANGEFS_FS = no;
        HUGETLBFS = no;
        CONFIGFS_FS = no;
        ISO9660_FS = no;
        MINIX_FS = no;

        # ====================================================================
        # UNUSED NETWORK DRIVERS
        # ====================================================================
        WLAN = no;                # No Wi-Fi on odin
        WIRELESS = no;            # No wireless
        WWAN = no;                # No mobile broadband
        NET_VENDOR_INTEL = no;
        NET_VENDOR_BROADCOM = no;
        NET_VENDOR_REALTEK = no;
        NET_VENDOR_ATHEROS = no;
        NET_VENDOR_CHELSIO = no;
        NET_VENDOR_CISCO = no;
        NET_VENDOR_MELLANOX = no;
        NET_VENDOR_MARVELL = no;
        NET_VENDOR_NETGEAR = no;
        NET_VENDOR_QLOGIC = no;
        NET_VENDOR_SAMSUNG = no;
        NET_VENDOR_SOLARFLARE = no;
        NET_VENDOR_TEHUTI = no;
        USB_NET_DRIVERS = no;

        # ====================================================================
        # UNUSED STORAGE (NVMe-only system)
        # ====================================================================
        ATA = no;                 # No PATA or SATA
        SATA_AHCI = no;
        PATA = no;
        SCSI = no;
        SCSI_LOWLEVEL = no;
        DM_MULTIPATH = no;
        DM_RAID = no;
        DM_THIN_PROVISIONING = no;
        DM_CACHE = no;
        DM_ERA = no;
        DM_LOG_WRITES = no;
        DM_INTEGRITY = no;
        DM_VERITY = no;
        DM_SNAPSHOT = no;
        MD_RAID = no;
        MD_LINEAR = no;
        MD_MULTIPATH = no;
        MD_FAULTY = no;

        # ====================================================================
        # UNUSED SOUND (keep USB audio — SND_USB set above)
        # ====================================================================
        SND_OTHER = no;
        SND_SOC = no;             # ALSA SoC for embedded

        # ====================================================================
        # UNUSED MEDIA / INPUT
        # ====================================================================
        MEDIA_SUPPORT = no;
        INPUT_TOUCHSCREEN = no;
        INPUT_TABLET = no;
        INPUT_MISC = no;
        RC_CORE = no;             # IR remote receivers

        # ====================================================================
        # UNUSED GPU DRIVERS (keep only DRM_AMDGPU above)
        # ====================================================================
        AGP = no;
        DRM_I915 = no;
        DRM_NOUVEAU = no;
        DRM_V3D = no;
        DRM_VMWGFX = no;
        DRM_BOCHS = no;
        DRM_CIRRUS_QEMU = no;
        DRM_QXL = no;
        DRM_VIRTIO_GPU = no;
        DRM_RADEON = no;

        # ====================================================================
        # UNUSED VIRTUALIZATION (KVM is set above, this is for other hypervisors)
        # ====================================================================
        XEN = no;
        VBOX = no;
        VMWARE = no;
        HYPERV = no;

        # ====================================================================
        # UNUSED MISC
        # ====================================================================
        MACINTOSH_DRIVERS = no;
        ISDN = no;
        USB_SERIAL = no;
      };
    }
  ];
}
