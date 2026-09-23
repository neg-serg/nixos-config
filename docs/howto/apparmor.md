# AppArmor — confining the network-facing daemons

AppArmor is enabled system-wide (`security.apparmor`), but nothing was confined: the shipped profile
sets attach to `/usr/sbin/*` and never match a Nix store binary. `modules/security/apparmor.nix`
closes that gap for eight daemons, with profiles **generated from each daemon's own package
closure** (`pkgs.apparmorRulesFromClosure`) so every file rule points at a real store path.

The first five are system units; the last three are session services (`user@1000`), which have no
unit hardening of their own — for them the profile is the only boundary.

| Daemon       | Attaches to                       | State option                              | Default    |
| ------------ | --------------------------------- | ----------------------------------------- | ---------- |
| sshd         | `…-openssh-*/bin/sshd`            | `features.security.apparmor.sshd`         | `complain` |
| unbound      | `…-unbound-*/bin/unbound`         | `features.security.apparmor.unbound`      | `complain` |
| AdGuard Home | `…-adguardhome-*/bin/AdGuardHome` | `features.security.apparmor.adguardhome`  | `complain` |
| ntfy-sh      | `…-ntfy-sh-*/bin/ntfy`            | `features.security.apparmor.ntfy`         | `complain` |
| avahi        | `…-avahi-*/bin/avahi-daemon`      | `features.security.apparmor.avahi`        | `complain` |
| sing-box     | `…-sing-box-*/bin/sing-box`       | `features.security.apparmor.singbox`      | `complain` |
| transmission | `…-transmission-*/bin/…-daemon`   | `features.security.apparmor.transmission` | `complain` |
| aria2        | `…-aria2-*/bin/aria2c`            | `features.security.apparmor.aria2`        | `complain` |

A profile attaches to the executable path, so a session service is confined exactly like a system
one — but note that one binary can back two units: `sing-box` is both the user SOCKS proxy and the
system `sing-box-tun` service, and a single profile covers both. The path in the profile is the
*resolved* one: `avahi-daemon` is exec'd as `…-avahi-0.8/sbin/avahi-daemon`, but `sbin/` is a
symlink to `bin/`, so the profile attaches to `…/bin/avahi-daemon` (same reason a rule for `/etc/x`
needs the store target behind the symlink — see below).

States are per daemon: `disable` (no profile at all), `complain` (denials are logged, nothing is
blocked), `enforce` (denials are blocked). The flag itself is `features.security.apparmor.enable`,
enabled in `hosts/odin/default.nix`.

## How a profile is built

```
abi <abi/4.0>,
include <tunables/global>

profile /nix/store/…-openssh-10.4p1/bin/sshd flags=(attach_disconnected) {
  include <abstractions/base>            # upstream abstractions, already patched
  include <abstractions/nameservice>     # by nixpkgs for the /etc symlink farm
  include <abstractions/authentication>  # (passwd/group/pam.d/shadow store paths)
  include "<apparmor-closure-rules>"     # every store path of the package closure
  …daemon-specific /etc, /run, /var rules, capabilities, network families…
  include if exists <local/sshd>         # local additions
}
```

Two details that bite on NixOS:

- **`/etc` is a symlink farm into the store** and AppArmor mediates the *resolved* path. A rule for
  `/etc/ssh/sshd_config` alone does not match `…-sshd.conf-final`. The module resolves those targets
  itself (the `etcFiles` field per daemon, mirroring nixpkgs'
  `nixos/modules/security/apparmor/includes.nix`); the shipped abstractions already do it for
  `passwd`/`group`/`hosts`/`resolv.conf`/`pam.d/*`. A name ending in `/` expands to every entry
  below it (`avahi/services/`), since each service file is its own store path.
- **The home directory is a symlink farm too.** nix-maid publishes managed files as store symlinks,
  so a rule for `~/.config/aria2/aria2.conf` does not match the file the daemon actually opens. The
  `homeFiles` field resolves those paths out of `users.users.<user>.maid.file.home` — again no
  `/nix/store` wildcards, and the rule follows the generation on every switch. This is what makes
  these two daemons enforceable: without it transmission would read no `settings.json` and fall back
  to default dirs, ports and RPC port.
- **The roddhjav profile set must stay off the include path.** Its `abstractions/crypto.d/complete`
  is pulled in by apparmor-profiles' `include if exists <abstractions/crypto.d>` and uses `@{lib}`,
  which Debian/Ubuntu provide in `tunables/multiarch.d/system` and NixOS does not. With it on the
  path every profile including `<abstractions/base>` dies with
  `Failed to find declaration for: @{lib}` and `apparmor.service` loads nothing. The package stays
  installed for reference only — see the comment in `modules/security/default.nix`.

## Inspect

```sh
just apparmor-status              # apparmor.service + aa-status (loaded profiles and modes)
just apparmor-denials             # every denial this boot
just apparmor-denials sshd        # only one daemon
```

`complain` denials are informational: the daemon worked, the rule is missing.

## Flip a daemon to enforce

1. Rebuild with the profile in `complain` and use the machine normally (a day is plenty) — including
   the paths that daemon rarely touches (an SSH login from another device, an AdGuard filter update,
   a DNS query for a new domain).

1. `just apparmor-denials <daemon>` and read what was denied.

1. Add the missing rules, either quickly via an include:

   ```nix
   security.apparmor.includes."local/sshd" = ''
     /var/log/lastlog rw,
   '';
   ```

   or permanently in the daemon's `rules` block in `modules/security/apparmor.nix`. Prefer the
   narrowest path the daemon actually needs.

1. Set the state to `"enforce"`, rebuild, then check the service and `just apparmor-status`.
   Profiles only apply to processes started *after* the switch (`killUnconfinedConfinables = false`
   on purpose — a running daemon keeps its old, unconfined state until it restarts).

A faster loop than editing the state in the repo: `sudo aa-complain <profile>` /
`sudo aa-enforce <profile>` switch a loaded profile at runtime (`aa-status` shows the current mode).

## Known limits

- **sshd sessions run unconfined on purpose** (`/bin/sh Ux`, `…/bin/bash Ux`, `…`): after the fork
  sshd execs the user's login shell and an interactive session legitimately runs arbitrary code.
  Confining it would break every login. The daemon and its privilege-separated child stay confined,
  which is where the pre-auth attack surface is.
- Only these four daemons are covered. User services (`mpd`, `transmission-daemon`, `sing-box`,
  `openrgb`) and desktop apps are not — upstream desktop profiles (browsers, Steam) assume FHS paths
  and would need the same closure treatment.
- `apparmor-profiles` is installed for its abstractions, not for its profiles.

## VM test

```sh
nix build --impure --file tests/apparmor-enforce.nix -L
```

Boots a throwaway VM with all four profiles in `enforce` and asserts: profiles loaded and enforcing,
all four services up, DNS/UI/ntfy ports open, SSH login **and** session command work, and no
`DENIED` lines for the confined daemons. This is the place to try a risky rule — a broken profile
fails the test, not the host.
