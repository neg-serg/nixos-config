##
# Module: system/filesystems-smallfiles
# Purpose: Optional mount options tuned for lots of small files (XFS/EXT4)
# Key options: profiles.performance.fs.smallFiles.* (disabled by default)
{ lib, config, ... }:
let
  cfg = config.profiles.performance.fs.smallFiles;
  types = lib.types;
  toStr = builtins.toString;
  mounts = cfg.mounts or [ ];
  fs = config.fileSystems;

  mkFor = m:
    let t = (fs.${m}.fsType or ""); in
    {
      fileSystems."${m}".options =
        lib.mkAfter (
          lib.optionals (t == "xfs" && (cfg.xfs.noatime or false)) [ "noatime" ]
          ++ lib.optionals (t == "ext4") (
            (lib.optional (cfg.ext4.noatime or false) "noatime")
            ++ (lib.optional (cfg.ext4.commitSec != null) ("commit=" + toStr cfg.ext4.commitSec))
          )
        );
    };

  rendered = lib.foldl' lib.mergeAttrs { } (map mkFor mounts);

in {
  options.profiles.performance.fs.smallFiles = {
    enable = lib.mkEnableOption "Enable optional XFS/EXT4 mount tweaks for many small files.";

    # Target mount points to which tweaks will be applied. Example: [ "/" "/one" "/zero" ]
    mounts = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of mount points to apply small-files options (only if their fsType matches).";
      example = [ "/" "/one" "/zero" ];
    };

    xfs = {
      noatime = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Add noatime for XFS mounts to cut atime metadata writes.";
      };
    };

    ext4 = {
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
