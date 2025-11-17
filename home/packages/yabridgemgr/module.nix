{
  self,
  system,
}: {
  config,
  lib,
  pkgs,
  ...
}:
with lib;
# Base config for all Linux systems
  let
    cfg = config.modules.audio-nix.yabridgemgr;
    mkBool =
      if (config ? lib) && (config.lib ? neg) && (config.lib.neg ? mkBool)
      then config.lib.neg.mkBool
      else (desc: default: (lib.mkEnableOption desc) // {inherit default;});
    # Minimal local presets helper for systemd user units
    presets = {
      defaultWanted = {
        after = [];
        wants = [];
        wantedBy = ["default.target"];
        partOf = [];
      };
      tmpfiles = {
        after = ["systemd-tmpfiles-setup.service"];
        wants = [];
        wantedBy = [];
        partOf = [];
      };
    };
    mkUnitFromPresets = args: let
      # args: { presets = ["defaultWanted" ...]; after ? [], wants ? [], partOf ? [], wantedBy ? [] }
      names = args.presets or [];
      accum =
        lib.foldl' (acc: n: {
          after = acc.after ++ (presets.${n}.after or []);
          wants = acc.wants ++ (presets.${n}.wants or []);
          partOf = acc.partOf ++ (presets.${n}.partOf or []);
          wantedBy = acc.wantedBy ++ (presets.${n}.wantedBy or []);
        }) {
          after = [];
          wants = [];
          partOf = [];
          wantedBy = [];
        }
        names;
      merged = {
        after = lib.unique (accum.after ++ (args.after or []));
        wants = lib.unique (accum.wants ++ (args.wants or []));
        partOf = lib.unique (accum.partOf ++ (args.partOf or []));
        wantedBy = lib.unique (accum.wantedBy ++ (args.wantedBy or []));
      };
    in {
      Unit =
        lib.optionalAttrs (merged.after != []) {After = merged.after;}
        // lib.optionalAttrs (merged.wants != []) {Wants = merged.wants;}
        // lib.optionalAttrs (merged.partOf != []) {PartOf = merged.partOf;};
      Install = lib.optionalAttrs (merged.wantedBy != []) {WantedBy = merged.wantedBy;};
    };
  in {
    options.modules.audio-nix.yabridgemgr = {
      enable = mkBool "Yabridgemgr" false;
      user = mkOption {
        type = types.str;
        description = "User for yabridgemgr";
      };
      plugins = mkOption {
        type = types.listOf types.package;
        default = [
          self.packages.${system}.wine-valhalla # Valhalla Supermassive (VST)
          self.packages.${system}.wine-voxengo-span # Voxengo SPAN analyzer (VST)
          self.packages.${system}.wine-midichordanalyzer # MIDI chord analyzer (VST)
        ];
        description = "Plugin packages to install";
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [
        pkgs.yabridge # Windows VST bridge for Linux hosts
        pkgs.yabridgectl # CLI to manage/sync bridged plugins
      ];
      systemd.user.tmpfiles.users."${cfg.user}".rules = let
        userHome = config.users.users.${cfg.user}.home;
        ybcfg = pkgs.writeText "yabridgecfg" ''
          plugin_dirs = [
            '${userHome}/yabridgemgr/drive_c/Program Files/Common Files/VST2',
            '${userHome}/yabridgemgr/drive_c/Program Files/Common Files/VST3',
          ]
          vst2_location = 'centralized'
          no_verify = false
          blacklist = []
        '';
      in [
        "d %h/yabridgemgr - - - - -"
        "C %h/.config/yabridgectl/config.toml - - - - ${ybcfg}"
      ];
      systemd.user.services = {
        yabridgemgr_mountprefix = let
          build_prefix = pkgs.callPackage ./plumbing/build_prefix.nix {
            username = cfg.user;
            inherit (cfg) plugins;
          };
          mount_prefix = pkgs.callPackage ./plumbing/mount_prefix.nix {
            wineprefix = build_prefix;
          };
          umount_prefix = pkgs.callPackage ./plumbing/umount_prefix.nix {};
        in lib.recursiveUpdate {
          Unit.Description = "Mount yabridge prefix";
          Service = {
            RuntimeDirectory = "yabridgemgr";
            ExecStart = let exe = "${mount_prefix}/bin/mount_prefix"; in "${exe}";
            ExecStop = let exe = "${umount_prefix}/bin/umount_prefix"; in "${exe}";
            RemainAfterExit = "yes";
          };
          Unit.ConditionUser = "${cfg.user}";
        } (mkUnitFromPresets {presets = ["tmpfiles" "defaultWanted"];});
        yabridgemgr_sync =
          lib.recursiveUpdate {
            Unit.Description = "yabridgectl sync";
            Service = {
              ExecStart = let
                exe = lib.getExe pkgs.yabridgectl;
                args = ["sync"];
              in "${exe} ${lib.escapeShellArgs args}";
              ExecStartPre = let
                exe = lib.getExe' pkgs.coreutils "sleep";
                args = ["5"];
              in "${exe} ${lib.escapeShellArgs args}";
              Environment = "NIX_PROFILES=/run/current-system/sw";
              RemainAfterExit = "yes";
            };
            Unit.ConditionUser = "${cfg.user}";
          } (mkUnitFromPresets {
            presets = ["defaultWanted"];
            after = ["yabridgemgr_mountprefix.service"];
          });
      };
    };
  }
