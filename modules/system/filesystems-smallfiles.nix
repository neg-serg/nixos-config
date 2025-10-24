##
# Module: system/filesystems-smallfiles
# Purpose: Optional mount options tuned for lots of small files (XFS/EXT4)
# Key options: profiles.performance.fs.smallFiles.* (disabled by default)
{ lib, config, ... }:
let
  cfg = config.profiles.performance.fs.smallFiles;
  types = lib.types;
  toStr = builtins.toString;
  mkForXfs = m: {
    fileSystems."${m}".options = lib.mkAfter (
      lib.optional (cfg.xfs.noatime or false) "noatime"
    );
  };
  mkForExt4 = m: {
    fileSystems."${m}".options = lib.mkAfter (
      (lib.optional (cfg.ext4.noatime or false) "noatime")
      ++ (lib.optional (cfg.ext4.commitSec != null) ("commit=" + toStr cfg.ext4.commitSec))
    );
  };
  rendered =
    lib.mergeAttrs
      (lib.foldl' lib.mergeAttrs { } (map mkForXfs cfg.xfs.mounts))
      (lib.foldl' lib.mergeAttrs { } (map mkForExt4 cfg.ext4.mounts));
in {
  options.profiles.performance.fs.smallFiles = {
    enable = lib.mkEnableOption "Enable optional XFS/EXT4 mount tweaks for many small files.";

    xfs = {
      mounts = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Mount points with XFS where to apply tweaks (e.g., noatime).";
        example = [ "/" "/one" "/zero" ];
      };
      noatime = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Add noatime for XFS mounts to cut atime metadata writes.";
      };
    };

    ext4 = {
      mounts = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Mount points with EXT4 where to apply tweaks (noatime, commit=).";
        example = [ "/data" ];
      };
      noatime = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Add noatime for EXT4 mounts to cut atime metadata writes.";
      };
      commitSec = lib.mkOption {
        type = types.nullOr types.ints.positive;
        default = 30; # conservative bump vs default 5s
        description = "Set EXT4 journal commit interval in seconds (higher reduces metadata IO; bigger crash window). Null to keep kernel default.";
        example = 30;
      };
    };
  };

  config = lib.mkIf (cfg.enable or false) rendered;
}
