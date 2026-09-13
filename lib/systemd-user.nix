{ lib }:
let
  presets = {
    graphical = {
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      partOf = [ ];
    };
    defaultWanted = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "default.target" ];
      partOf = [ ];
    };
    timers = {
      after = [ ];
      wants = [ ];
      wantedBy = [ "timers.target" ];
      partOf = [ ];
    };
    net = {
      after = [ "network.target" ];
      wants = [ ];
      wantedBy = [ ];
      partOf = [ ];
    };
    netOnline = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ ];
      partOf = [ ];
    };
    sops = {
      after = [ "sops-nix.service" ];
      wants = [ "sops-nix.service" ];
      wantedBy = [ ];
      partOf = [ ];
    };
    dbusSocket = {
      after = [ "dbus.socket" ];
      wants = [ ];
      wantedBy = [ ];
      partOf = [ ];
    };
    socketsTarget = {
      after = [ "sockets.target" ];
      wants = [ ];
      wantedBy = [ ];
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

  mkSimpleService =
    {
      name,
      execStart,
      presets ? [ ],
      description ? null,
      serviceExtra ? { },
      unitExtra ? { },
      after ? [ ],
      wants ? [ ],
      partOf ? [ ],
      wantedBy ? [ ],
    }:
    {
      systemd.user.services."${name}" =
        lib.recursiveUpdate
          {
            Unit = (lib.optionalAttrs (description != null) { Description = description; }) // unitExtra;
            Service = {
              ExecStart = execStart;
            }
            // serviceExtra;
          }
          (mkUnitFromPresets {
            inherit
              presets
              after
              wants
              partOf
              wantedBy
              ;
          });
    };

  mkSimpleTimer =
    {
      name,
      presets ? [ ],
      description ? null,
      onCalendar ? null,
      accuracySec ? null,
      persistent ? null,
      timerExtra ? { },
      unitExtra ? { },
      after ? [ ],
      wants ? [ ],
      partOf ? [ ],
      wantedBy ? null,
    }:
    let
      finalWantedBy =
        if wantedBy != null then wantedBy else (lib.optional (lib.elem "timers" presets) "timers.target");
    in
    {
      systemd.user.timers."${name}" =
        lib.recursiveUpdate
          {
            Unit = (lib.optionalAttrs (description != null) { Description = description; }) // unitExtra;
            Timer =
              { }
              // lib.optionalAttrs (onCalendar != null) { OnCalendar = onCalendar; }
              // lib.optionalAttrs (accuracySec != null) { AccuracySec = accuracySec; }
              // lib.optionalAttrs (persistent != null) { Persistent = persistent; }
              // timerExtra;
          }
          (mkUnitFromPresets {
            inherit
              presets
              after
              wants
              partOf
              ;
            wantedBy = finalWantedBy;
          });
    };

  mkSimpleSocket =
    {
      name,
      presets ? [ ],
      description ? null,
      listenStream ? null,
      listenDatagram ? null,
      listenFIFO ? null,
      socketExtra ? { },
      unitExtra ? { },
      after ? [ ],
      wants ? [ ],
      partOf ? [ ],
      wantedBy ? null,
    }:
    let
      finalWantedBy =
        if wantedBy != null then
          wantedBy
        else
          (lib.optional (lib.elem "socketsTarget" presets) "sockets.target");
    in
    {
      systemd.user.sockets."${name}" =
        lib.recursiveUpdate
          {
            Unit = (lib.optionalAttrs (description != null) { Description = description; }) // unitExtra;
            Socket =
              { }
              // lib.optionalAttrs (listenStream != null) { ListenStream = listenStream; }
              // lib.optionalAttrs (listenDatagram != null) { ListenDatagram = listenDatagram; }
              // lib.optionalAttrs (listenFIFO != null) { ListenFIFO = listenFIFO; }
              // socketExtra;
          }
          (mkUnitFromPresets {
            inherit
              presets
              after
              wants
              partOf
              ;
            wantedBy = finalWantedBy;
          });
    };
}
