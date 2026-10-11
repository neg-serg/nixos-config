{ lib }:
let
  # A preset carries two kinds of defaults:
  #   - scheduling: after / wants / partOf / wantedBy (accumulated, unique);
  #   - service:    serviceConfig keys (Restart/RestartSec/Type/…), merged
  #                 left to right, the caller's own serviceConfig wins last.
  # Keep every list key present (empty when unused) — the other kind is `or [ ]`-safe.
  presets = {
    # Autostart in the user manager's default target — the common case.
    defaultWanted = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "default.target" ];
      partOf = [ ];
    };
    # Long-running unit policy: the repo-wide "restart unless it exited cleanly".
    # Deliberately NO RestartSec: the delay varies per unit (1…30 s), so a unit
    # that wants one passes it in its own serviceConfig (the call site keeps the
    # number, the preset keeps the policy).
    restartOnFailure = {
      after = [ ];
      wants = [ ];
      wantedBy = [ ];
      partOf = [ ];
      service = {
        Restart = "on-failure";
      };
    };
    # Short-lived helper: no restart policy of its own and no target — the
    # caller says whether it is wanted by default.target, a timer, or nothing.
    oneshot = {
      after = [ ];
      wants = [ ];
      wantedBy = [ ];
      partOf = [ ];
      service = {
        Type = "oneshot";
      };
    };
    # Resident in the graphical session (bar/portal/theme helpers).
    # PartOf: the unit follows the session down. Use `graphicalWanted` when the
    # unit only needs to be pulled in by the session, not stopped with it.
    graphicalSession = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
    };
    graphicalWanted = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "graphical-session.target" ];
      partOf = [ ];
    };
  };

  # mergeList — preset/argument list merge that a caller can escape.
  mergeList =
    accumulated: extra:
    # `lib.mkForce`/`mkOverride` value (a priority wrapper, not a list): pass it
    # through untouched — the caller is deliberately overriding another module's
    # ordering (e.g. tailray after = mkForce [ … ]), so merging would either
    # crash lib.unique or silently demote the override.
    if lib.isAttrs extra && (extra ? _type) then extra else lib.unique (accumulated ++ extra);

  mkUnitFromPresets =
    args:
    let
      names = args.presets or [ ];
      accum =
        lib.foldl'
          (acc: n: {
            after = acc.after ++ (presets.${n}.after or [ ]);
            wants = acc.wants ++ (presets.${n}.wants or [ ]);
            requires = acc.requires ++ (presets.${n}.requires or [ ]);
            bindsTo = acc.bindsTo ++ (presets.${n}.bindsTo or [ ]);
            partOf = acc.partOf ++ (presets.${n}.partOf or [ ]);
            wantedBy = acc.wantedBy ++ (presets.${n}.wantedBy or [ ]);
            service = acc.service // (presets.${n}.service or { });
          })
          {
            after = [ ];
            wants = [ ];
            requires = [ ];
            bindsTo = [ ];
            partOf = [ ];
            wantedBy = [ ];
            service = { };
          }
          names;
      merged = {
        after = mergeList accum.after (args.after or [ ]);
        wants = mergeList accum.wants (args.wants or [ ]);
        requires = mergeList accum.requires (args.requires or [ ]);
        bindsTo = mergeList accum.bindsTo (args.bindsTo or [ ]);
        partOf = mergeList accum.partOf (args.partOf or [ ]);
        wantedBy = mergeList accum.wantedBy (args.wantedBy or [ ]);
      };
    in
    {
      Unit =
        lib.optionalAttrs (merged.after != [ ]) { After = merged.after; }
        // lib.optionalAttrs (merged.wants != [ ]) { Wants = merged.wants; }
        // lib.optionalAttrs (merged.requires != [ ]) { Requires = merged.requires; }
        // lib.optionalAttrs (merged.bindsTo != [ ]) { BindsTo = merged.bindsTo; }
        // lib.optionalAttrs (merged.partOf != [ ]) { PartOf = merged.partOf; };
      Install = lib.optionalAttrs (merged.wantedBy != [ ]) { WantedBy = merged.wantedBy; };
      # serviceConfig defaults from the presets; mkUserService merges the
      # caller's own serviceConfig on top (caller wins per key).
      Service = accum.service;
    };
in
# rec: mkUserOneshot is a thin wrapper over mkUserService (the presets table
# owns the unit policy), so the two sibling attributes must see each other.
rec {
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
    # The initrd stage runs the activation scripts too (NixOS shares one activation
    # tree), and a user-plane caretaker has no business there: /run/current-system is
    # not mounted yet in that chroot, so a PATH lookup for jq/diffutils fails and the
    # caretaker either dies mid-run (set -e) or — worse — takes the "changed" branch
    # and rewrites files nobody reads yet. The root stage and the login services do
    # the real work. Guarded here, once, for every caller.
    # The runuser call keeps its `|| true`: a caretaker failing must not abort
    # the activation.
    lib.stringAfter after ''
      [ -d /run/current-system ] && ${runAsUser} -u ${user} -- env HOME=${home} ${script} || true
    '';

  # Login half: oneshot wanted by default.target. Returns the unit definition
  # (without the attribute name). Thin wrapper over the "oneshot" + "defaultWanted"
  # presets — the unit policy lives in the preset table above, not here.
  mkUserOneshot =
    {
      description,
      script,
      after ? [ ],
    }:
    mkUserService {
      presets = [
        "defaultWanted"
        "oneshot"
      ];
      inherit description after;
      serviceConfig = {
        ExecStart = script;
      };
    };

  # Shared constructor behind mkUserService/mkSystemService: one preset table
  # and one merge order for both unit shapes. `enable ? null` emits the key
  # only when a caller overrides it; mkUserService pins its default to true
  # because the user option shape always carries the key.
  mkService =
    {
      description ? null,
      presets ? [ ],
      after ? [ ],
      wants ? [ ],
      requires ? [ ],
      bindsTo ? [ ],
      partOf ? [ ],
      wantedBy ? [ ],
      serviceConfig ? { },
      unitConfig ? { },
      # Unit-level fields the module shape carries outside unitConfig; emitted
      # only when non-empty, so a caller that omits them gets the bare shape.
      documentation ? [ ],
      environment ? { },
      path ? [ ],
      enable ? null,
    }:
    let
      schedule = mkUnitFromPresets {
        inherit
          presets
          after
          wants
          requires
          bindsTo
          partOf
          wantedBy
          ;
      };
      unit = schedule.Unit or { };
      # Preset-provided service keys first, the caller's overrides last.
      service = (schedule.Service or { }) // serviceConfig;
    in
    lib.optionalAttrs (enable != null) { inherit enable; }
    // lib.optionalAttrs (description != null) { inherit description; }
    // lib.optionalAttrs (path != [ ]) { inherit path; }
    // lib.optionalAttrs (unitConfig != { }) { inherit unitConfig; }
    // lib.optionalAttrs (service != { }) { serviceConfig = service; }
    // lib.optionalAttrs (documentation != [ ]) { inherit documentation; }
    // lib.optionalAttrs (environment != { }) { inherit environment; }
    // lib.optionalAttrs ((unit.After or [ ]) != [ ]) { after = unit.After; }
    // lib.optionalAttrs ((unit.Wants or [ ]) != [ ]) { wants = unit.Wants; }
    // lib.optionalAttrs ((unit.Requires or [ ]) != [ ]) { requires = unit.Requires; }
    // lib.optionalAttrs ((unit.BindsTo or [ ]) != [ ]) { bindsTo = unit.BindsTo; }
    // lib.optionalAttrs ((unit.PartOf or [ ]) != [ ]) { partOf = unit.PartOf; }
    // lib.optionalAttrs (((schedule.Install or { }).WantedBy or [ ]) != [ ]) {
      wantedBy = schedule.Install.WantedBy;
    };

  # Module-shaped user unit for `systemd.user.services.<name>` — the shape the
  # hand-rolled units in this repo use (description / unitConfig / serviceConfig
  # / path / enable plus the module's own after/wants/partOf/wantedBy). The raw
  # `Unit`/`Service`/`Install` shape that once lived here (mkSimpleService/
  # mkSimpleTimer/mkSimpleSocket) had no callers and was removed with the C6
  # audit item (2026-09-15).
  #
  #   systemd.user.services.foo = systemdUser.mkUserService {
  #     description = "…";
  #     presets = [ "defaultWanted" "restartOnFailure" ];   # scheduling + service policy
  #     serviceConfig = { ExecStart = "…"; RestartSec = 3; };  # wins over the preset
  #     unitConfig = { ConditionUser = "!greeter"; };   # optional
  #     path = [ pkgs.inotify-tools ];                  # optional
  #   };
  #
  # Only the fields the caller provides end up in the unit, so a migrated unit
  # evaluates to exactly the same attrset as the hand-written one — except for
  # the keys a preset contributes (a preset adds, the caller's value still wins).
  mkUserService = args: mkService (args // { enable = args.enable or true; });

  # System-level twin of mkUserService for `systemd.services.<name>` — same
  # presets and merge order, so the system and user sides share one policy
  # table. The only shape difference is `enable`: the system option already
  # defaults to true, so the key is emitted only when a caller overrides it
  # (the user shape always carries it).
  #
  #   systemd.services.foo = systemdUser.mkSystemService {
  #     description = "…";
  #     presets = [ "restartOnFailure" ];                    # Restart=on-failure
  #     serviceConfig = { ExecStart = "…"; RestartSec = 5; };  # delay stays here
  #     wantedBy = [ "multi-user.target" ];
  #   };
  mkSystemService = mkService;

  # System-level oneshot service + matching timer (emits `systemd.services` /
  # `systemd.timers`, not user units) — the shape hosts/trantor repeats. Returns a
  # fragment keyed by `name`, so the caller keeps its own gating and `config =` key:
  #
  #   config = lib.mkIf cond (systemdUser.mkOneshotTimer {
  #     name = "telegram-digest"; description = "…"; timerDescription = "…";
  #     script = lib.getExe telegramDigestScript;      # ExecStart, verbatim
  #     onCalendar = "*-*-* 08:00:00";                 # or onBootSec[/OnUnitActiveSec]
  #     restartSec = 30; stateDirectory = "telegram-digest";   # default 60
  #   });
  # Implied: Type = "oneshot", Unit = "<name>.service", WantedBy = timers.target
  # and, unless `networkOnline = false`, After = Wants = network-online.target
  # (`after` appends extra After= entries; `restart = null` drops Restart and
  # RestartSec). Persistent is never set: on VM snapshot restores / boot
  # catch-ups systemd would otherwise fire missed runs.
  mkOneshotTimer =
    {
      name,
      description,
      timerDescription,
      script,
      onCalendar ? null,
      onBootSec ? null,
      onUnitActiveSec ? null,
      networkOnline ? true,
      after ? [ ],
      wantedBy ? [ ],
      restart ? "on-failure",
      restartSec ? 60,
      stateDirectory ? null,
    }:
    let
      serviceAfter = lib.unique (lib.optional networkOnline "network-online.target" ++ after);
    in
    {
      systemd.services.${name} = lib.filterAttrs (_: v: v != [ ]) {
        inherit description;
        serviceConfig = lib.filterAttrs (_: v: v != null) {
          Type = "oneshot";
          ExecStart = script;
          Restart = restart;
          RestartSec = if restart == null then null else restartSec;
          StateDirectory = stateDirectory;
        };
        after = serviceAfter;
        wants = lib.optional networkOnline "network-online.target";
        inherit wantedBy;
      };

      systemd.timers.${name} = {
        description = timerDescription;
        wantedBy = [ "timers.target" ];
        timerConfig = lib.filterAttrs (_: v: v != null) {
          OnCalendar = onCalendar;
          OnBootSec = onBootSec;
          OnUnitActiveSec = onUnitActiveSec;
          Unit = "${name}.service";
        };
      };
    };

}
