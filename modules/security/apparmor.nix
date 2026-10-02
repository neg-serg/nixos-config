##
# Module: security/apparmor
# Purpose: AppArmor confinement for the network-facing daemons: the system
#   services (sshd, unbound, AdGuard Home, ntfy-sh, avahi) and the session ones
#   that parse network data as the login user (sing-box, transmission, aria2).
#   A profile attaches to the executable path, so it confines a user-session
#   service just as well as a system unit — and for those it is the only
#   boundary, since unit hardening (ProtectSystem=…) does not apply to them.
#   Every profile is generated from the daemon's own package closure
#   (pkgs.apparmorRulesFromClosure), so the file rules point at real Nix store
#   paths instead of the FHS paths upstream profiles assume — that is the
#   reason the shipped apparmor-profiles / roddhjav sets are NOT loaded here:
#   they attach to /usr/sbin/* and would never match a NixOS binary.
#   A profile only adds what the closure cannot know: state under /etc, /run
#   and /var, capabilities, network families. Local additions go through
#   security.apparmor.includes."local/<daemon>": every profile ends with
#   `include if exists <local/<daemon>>`. /etc is a read-only store symlink
#   farm on NixOS, so there is no writable /etc/apparmor.d/local to edit at
#   runtime — the include exists so a rule can be added from the config
#   without touching the profile body.
#   Both /etc and the home directory are symlink farms into the store and
#   AppArmor mediates the resolved path, so the module resolves them itself:
#   `etcFiles` for /etc (a trailing "/" expands to the whole subdirectory),
#   `homeFiles` for the nix-maid managed files under the main user's home.
#   Neither wildcards /nix/store, and both follow the generation on a switch.
#   (See docs/howto/apparmor.md for the iteration loop.)

# Key options: features.security.apparmor.{enable,sshd,unbound,adguardhome,ntfy,avahi,singbox,transmission,aria2}
#   Each daemon is independent: "disable" | "complain" | "enforce".
#   Defaults ship every profile in "complain" (denials are logged, nothing is
#   blocked). Flip one daemon to "enforce" only after its denials in
#   `journalctl -b --grep 'apparmor="DENIED"'` have been reviewed — see
#   docs/howto/apparmor.md.
#   apparmor.service loads /etc/apparmor.d (built from these policies) before
#   sysinit.target, so daemons start confined on the next boot; a `switch`
#   reloads/replaces profiles for the *next* exec of each binary.
# Dependencies: security.apparmor (this domain), pkgs.apparmor-profiles and
#   pkgs.roddhjav-apparmor-rules for the abstractions (base, nameservice,
#   ssl_certs) referenced from the include paths.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.security.apparmor;

  # The primary user: owns the session services below and the nix-maid file
  # tree their config files come from. The fallback keeps the module evaluable
  # in tests/apparmor-enforce.nix, which does not import the repo's option set.
  mainUser = config.lib.neg.mainUser or "neg";

  # NixOS' /etc is a symlink farm into the store and AppArmor mediates the
  # *resolved* path, so a rule for /etc/<name> alone does not match the file
  # behind it. nixpkgs' own abstractions patch this the same way (see
  # nixos/modules/security/apparmor/includes.nix) — here it covers the
  # daemon-specific files that no shipped abstraction knows about.
  etcSource =
    name:
    let
      entry = config.environment.etc.${name} or null;
    in
    lib.optional (entry != null) entry.source;

  # A name ending in "/" expands to every environment.etc entry below it:
  # avahi publishes one file per service in /etc/avahi/services/, each a
  # directory entry pointing at its own store path, and each needs its own
  # resolved rule (a rule for the directory covers the listing, not the file).
  etcKeys =
    names:
    lib.concatMap (
      name:
      if lib.hasSuffix "/" name then
        lib.filter (k: lib.hasPrefix name k) (lib.attrNames config.environment.etc)
      else
        [ name ]
    ) names;

  # Files under the home directory reach a daemon through a symlink into the
  # store as well (nix-maid publishes them that way), and AppArmor mediates the
  # resolved path — the same trap as /etc. Resolve the store path out of
  # nix-maid's own file tree (users.users.<mainUser>.maid.file.home) instead of
  # wildcarding /nix/store; the path is regenerated on every switch, so the
  # rule follows the generation.
  maidStoreFile =
    relative:
    let
      files = config.users.users.${mainUser}.maid.file.home or { };
      entry = files.${relative} or null;
    in
    lib.optional (entry != null && entry.source != null) entry.source;

  # A few modules render their config into the store and pass the path on the
  # command line instead of publishing it in environment.etc (ntfy's
  # server.yml). Read it back from the rendered unit rather than wildcarding
  # the whole store.
  execStartPath =
    unit: flag:
    let
      match = builtins.match ".* ${flag} (/nix/store/[^ ]+).*" (
        toString config.systemd.services.${unit}.serviceConfig.ExecStart
      );
    in
    lib.optional (match != null) (builtins.head match);

  # Per-daemon profile data (executable, package closure, /etc and home paths,
  # extra includes, literal rules) lives in the sibling data file; the module
  # keeps the options, the complain/enforce gating and the mkProfile renderer.
  daemons = import ./apparmor-profiles.nix { inherit config pkgs execStartPath; };

  # Indent the rule block by two spaces and keep a trailing newline so the
  # rendered /etc/apparmor.d/<name> file stays readable (diffable against
  # aa-logprof output).
  indent = text: lib.concatMapStrings (line: "  ${line}\n") (lib.splitString "\n" text);

  mkProfile =
    name: daemon:
    let
      helperPackages = daemon.extraPackages or [ ];
      header = [
        "abi <abi/4.0>,"
        "include <tunables/global>"
        ""
        "# Generated by modules/security/apparmor.nix — do not edit in place:"
        "# local rules belong in security.apparmor.includes.\"local/${name}\"."
        "profile ${daemon.package}/bin/${daemon.exe} flags=(attach_disconnected) {"
        "  include <abstractions/base>"
        "  include <abstractions/nameservice>"
        "  include <abstractions/ssl_certs>"
      ];
      includes = map (i: "  include ${i}") (daemon.extraIncludes or [ ]);
      # /etc entries and generated store files the daemon reads.
      storePaths = map (p: "  ${p} r,") (
        (lib.concatMap etcSource (etcKeys (daemon.etcFiles or [ ])))
        ++ (daemon.extraPaths or [ ])
        ++ (lib.concatMap maidStoreFile (daemon.homeFiles or [ ]))
      );
      # Helper binaries the daemon shells out to: their closure must be
      # readable and the binaries executable inside this profile.
      helperClosure =
        lib.optional (helperPackages != [ ])
          ''include "${pkgs.apparmorRulesFromClosure { name = "neg-${name}-extra"; } helperPackages}"'';
      helperExec = map (p: "  ${p}/bin/* ixr,") helperPackages;
      body = [
        "  # The attached binary itself (the attachment only grants the profile"
        "  # transition, not the read)."
        "  ${daemon.package}/bin/${daemon.exe} mr,"
        "  include \"${pkgs.apparmorRulesFromClosure { name = "neg-${name}"; } [ daemon.package ]}\""
      ];
      ruleLines = lib.splitString "\n" (lib.removeSuffix "\n" (indent (lib.trim daemon.rules)));
    in
    lib.concatStringsSep "\n" (
      header
      ++ includes
      ++ storePaths
      ++ helperClosure
      ++ helperExec
      ++ body
      ++ ruleLines
      ++ [
        "  include if exists <local/${name}>"
        "}"
      ]
    )
    + "\n";

  enabledDaemons = lib.filterAttrs (name: _: cfg.${name} != "disable") daemons;
in
{
  config = lib.mkIf cfg.enable {
    security.apparmor.policies = lib.mapAttrs' (name: daemon: {
      inherit name;
      value = {
        state = cfg.${name};
        profile = mkProfile name daemon;
      };
    }) enabledDaemons;
  };
}
