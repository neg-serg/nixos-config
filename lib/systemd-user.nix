{ lib }:
let
  presets = {
    defaultWanted = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "default.target" ];
      partOf = [ ];
    };
  };

  mkUnitFromPresets =
    args:
    let
      names = args.presets or [ ];
      accum =
        lib.foldl'
          (acc: n: {
            after = acc.after ++ (presets.${n}.after or [ ]);
            wants = acc.wants ++ (presets.${n}.wants or [ ]);
            partOf = acc.partOf ++ (presets.${n}.partOf or [ ]);
            wantedBy = acc.wantedBy ++ (presets.${n}.wantedBy or [ ]);
          })
          {
            after = [ ];
            wants = [ ];
            partOf = [ ];
            wantedBy = [ ];
          }
          names;
      merged = {
        after = lib.unique (accum.after ++ (args.after or [ ]));
        wants = lib.unique (accum.wants ++ (args.wants or [ ]));
        partOf = lib.unique (accum.partOf ++ (args.partOf or [ ]));
        wantedBy = lib.unique (accum.wantedBy ++ (args.wantedBy or [ ]));
      };
    in
    {
      Unit =
        lib.optionalAttrs (merged.after != [ ]) { After = merged.after; }
        // lib.optionalAttrs (merged.wants != [ ]) { Wants = merged.wants; }
        // lib.optionalAttrs (merged.partOf != [ ]) { PartOf = merged.partOf; };
      Install = lib.optionalAttrs (merged.wantedBy != [ ]) { WantedBy = merged.wantedBy; };
    };
in
{
  inherit presets mkUnitFromPresets;

  # Per-user caretaker pattern, in two value-returning halves (callers keep
  # their own literal `system.activationScripts.<name>` / `systemd.user.services.<name>`
  # keys — the module shape must not depend on config, see modules/core/neg.nix).
  #
  # user/home come from config.lib.neg.mainUser / .homeDir; script is a store
  # path from writeShellScript (used verbatim as ExecStart).
  #
  # Run script as the primary user on every rebuild (root drops to the user via
  # runuser); after lists the activation snippets this one must follow.
  mkUserActivation =
    {
      pkgs,
      user,
      home,
      script,
      after ? [ "users" ],
    }:
    let
      runAsUser = lib.getExe' pkgs.util-linux "runuser";
    in
    # Same evaluated text as the hand-written blocks this replaces
    # ("<cmd> || true\n": Nix strips the common indent of an indented string),
    # so the generated activation script is byte-identical.
    lib.stringAfter after ''
      ${runAsUser} -u ${user} -- env HOME=${home} ${script} || true
    '';

  # Login half: oneshot wanted by default.target. Returns the unit definition
  # (without the attribute name).
  mkUserOneshot =
    {
      description,
      script,
      after ? [ ],
    }:
    {
      enable = true;
      inherit description;
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = script;
      };
    }
    // lib.optionalAttrs (after != [ ]) { inherit after; };

  # Module-shaped user unit for `systemd.user.services.<name>` — the shape the
  # hand-rolled units in this repo use (description / unitConfig / serviceConfig
  # / path / enable plus the module's own after/wants/partOf/wantedBy). The raw
  # `Unit`/`Service`/`Install` shape that once lived here (mkSimpleService/
  # mkSimpleTimer/mkSimpleSocket) had no callers and was removed with the C6
  # audit item (2026-09-15).
  #
  #   systemd.user.services.foo = systemdUser.mkUserService {
  #     description = "…";
  #     presets = [ "defaultWanted" ];                  # scheduling presets
  #     serviceConfig = { ExecStart = "…"; Restart = "on-failure"; };
  #     unitConfig = { ConditionUser = "!greeter"; };   # optional
  #     path = [ pkgs.inotify-tools ];                  # optional
  #   };
  #
  # Only the fields the caller provides end up in the unit, so a migrated unit
  # evaluates to exactly the same attrset as the hand-written one.
  mkUserService =
    {
      description ? null,
      presets ? [ ],
      after ? [ ],
      wants ? [ ],
      partOf ? [ ],
      wantedBy ? [ ],
      serviceConfig ? { },
      unitConfig ? { },
      path ? [ ],
      enable ? true,
    }:
    let
      schedule = mkUnitFromPresets {
        inherit
          presets
          after
          wants
          partOf
          wantedBy
          ;
      };
      unit = schedule.Unit or { };
    in
    {
      inherit enable;
    }
    // lib.optionalAttrs (description != null) { inherit description; }
    // lib.optionalAttrs (path != [ ]) { inherit path; }
    // lib.optionalAttrs (unitConfig != { }) { inherit unitConfig; }
    // lib.optionalAttrs (serviceConfig != { }) { inherit serviceConfig; }
    // lib.optionalAttrs ((unit.After or [ ]) != [ ]) { after = unit.After; }
    // lib.optionalAttrs ((unit.Wants or [ ]) != [ ]) { wants = unit.Wants; }
    // lib.optionalAttrs ((unit.PartOf or [ ]) != [ ]) { partOf = unit.PartOf; }
    // lib.optionalAttrs (((schedule.Install or { }).WantedBy or [ ]) != [ ]) {
      wantedBy = schedule.Install.WantedBy;
    };

}
