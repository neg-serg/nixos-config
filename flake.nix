{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    # Dendritic pilot: `flake/devshells/` walks itself, so a new shell file needs
    # no list entry. `vic/import-tree` is the pattern's walker — deps-free, no
    # inputs of its own, MIT — pinned by flake.lock.
    import-tree.url = "github:vic/import-tree";
    # Dendritic parts layer: every file under `flake/parts/` declares its
    # outputs; flake-parts gives `flake.*`/`perSystem` their shape. Pinned to
    # the rev the prototype was measured at.
    flake-parts.url = "github:hercules-ci/flake-parts/ea2630b7470978622c7689a1ff75d2b389175399";
    # Determinate Nix 3.23.3 (determinate + nix-src share the release tag on
    # purpose — the module installs the determinate-nixd binary that pairs with
    # the nix build, so bump both together). Bumped from 3.21.7: on that rev
    # packaging/everything.nix and src/perl/package.nix still used the deprecated
    # `stdenv.isLinux`/`stdenv.isDarwin` attributes, which every rebuild printed
    # as evaluation warnings; 3.23.3 uses hostPlatform and dropped the Perl
    # bindings. Re-lock with `just update` or:
    #   nix flake lock --update-input determinate --update-input nix-src
    determinate = {
      url = "github:DeterminateSystems/determinate/5f516660eb6faa93f5cb83ef493345967ca719ef";
      inputs.nix.follows = "nix-src";
      # Determinate's own nixpkgs pins flakehub nixpkgs-weekly, which is
      # unreachable from this host; follow the top-level nixpkgs input instead.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-src = {
      url = "github:DeterminateSystems/nix-src/74d688aa7b83ee1894ac1881eb3421b4c3fe3677";
      inputs.nixpkgs.follows = "nixpkgs";
      # nix-src's other nixpkgs inputs are test fixtures of Nix's own test
      # suite (`nix flake check` upstream), not build inputs: nothing here runs
      # them, so point them at the system pin too. The lock then carries no
      # extra nixpkgs snapshots at all.
      inputs.nixpkgs-23-11.follows = "nixpkgs";
      inputs.nixpkgs-regression.follows = "nixpkgs";
    };
    # Moved to nixos-unstable (2026-08) for newer Hyprland/color-mgmt
    # (ICC + HDR). Deliberate, even though it re-locks nixpkgs: the pin from
    # nixos-26.05 (commit e16f4269, which reverted the weekly experiment) had
    # a stable Hyprland 0.55.4; unstable tracks 0.56+ with HDR/color-management
    # and keeps the compositor ecosystem in sync. Re-align drift with:
    #   nix flake lock --update-input nixpkgs
    #
    # Pinned to a concrete unstable HEAD rev because nix (in this repo/state)
    # refuses to re-resolve the floating `nixos-unstable` ref from the lock's
    # stale `nixos-25.11`/`nixos-26.05` originals (nix flake update/lock/
    # --recreate-lock-file all leave it at the old rev). Bump this rev with
    # `nix flake lock --update-input nixpkgs` once the ref resolution settles.
    # The current rev is the published nixos-unstable channel release of
    # 2026-11-21 (Hyprland 0.57.2, Herdr 0.9.5): a channel release keeps the
    # closure substitutable from cache.nixos.org instead of building from
    # source, and Herdr >= 0.9.2 is what enables native agent-session restore.
    nixpkgs.url = "github:NixOS/nixpkgs/2786a2a72088ecf32aea5b3ec52099e6a7cff78f";

    raise = {
      url = "github:neg-serg/raise";
      # Without follows the input pins its own nixpkgs, and every raise build
      # carried a second toolchain into the system closure: glibc 2.40 (31 MiB)
      # plus gcc-14.3-lib, libidn2, libunistring — 41 MiB reachable only through
      # raise. Its naersk build works against the system nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # tint — colouriser for CLI output, extracted to its own project
    # (github:neg-serg/tint). It owns its packaging and tests; this flake only
    # consumes the package, so the two copies cannot drift.
    tint = {
      url = "github:neg-serg/tint";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # tgchat-rs — Telegram chat access over a grammers user session, extracted
    # to github:neg-serg/tgchat-rs, which owns its packaging, tests and CI.
    tgchat-rs = {
      url = "github:neg-serg/tgchat-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # telegram-notify — the host's Telegram notification binaries and the
    # assistant bot, extracted to github:neg-serg/telegram-notify. Only the
    # source and the packaging moved: every path, chat id and secret location
    # stays environment-driven, so the systemd units keep their contract.
    telegram-notify = {
      url = "github:neg-serg/telegram-notify";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sing-box-proxy — the sing-box SOCKS proxy controller, extracted to
    # github:neg-serg/sing-box-proxy. The crate owns its packaging; the host
    # keeps the user unit, the secrets and the network feature flags.
    sing-box-proxy = {
      url = "github:neg-serg/sing-box-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # music-index-tools — build/query the MERT similarity index, extracted to
    # github:neg-serg/music-index-tools, which owns the crate, its packaging,
    # the README and the self-check; this flake only consumes the package, so
    # the two copies cannot drift.

    music-index-tools = {
      url = "github:neg-serg/music-index-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mpd-voice — voice control for MPD over local speech recognition, extracted
    # to github:neg-serg/mpd-voice, which owns the crate, its packaging, the
    # README and the flake checks; this flake only consumes the package.
    mpd-voice = {
      url = "github:neg-serg/mpd-voice";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hypr-win-list — the Hyprland window picker, extracted to
    # github:neg-serg/hypr-win-list, which owns the crate, its packaging, the
    # README and the fixture check; this flake only consumes the package.
    hypr-win-list = {
      url = "github:neg-serg/hypr-win-list";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # shtoy — open Shadertoy shaders in esshader, extracted to
    # github:neg-serg/shtoy, which owns the crate, its packaging, the README and
    # the CLI check; this flake only consumes the package.
    shtoy = {
      url = "github:neg-serg/shtoy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # rust-pkgs — the Rust crates that used to live in packages/: the
    # local-bin-* $PATH helpers, hwctl, game, tidalctl, questyle-ctl, wineapps
    # and the rest. The repository owns their manifests, lockfiles, the shared
    # meta builder and the slimming wrapper; this flake calls
    # `final.callPackage (inputs.rust-pkgs + "/<crate>/package.nix") { }` so the
    # binaries keep building against this flake's package set (hyprland, wine,
    # sqlite) and the pkgs.neg.* attribute names stay unchanged.
    rust-pkgs = {
      url = "github:neg-serg/rust-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # genlc — Genelec SAM monitor control over the GLM USB adapter, extracted
    # to github:neg-serg/genlc, which owns the crate, its packaging and the CLI
    # check; this flake only consumes the package. The host keeps the adapter's
    # udev rule and the `genlc daemon` user unit.
    genlc = {
      url = "github:neg-serg/genlc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wl = {
      url = "github:neg-serg/wl";
      flake = false;
    };

    iosevka-neg = {
      url = "github:neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lusty = {
      url = "github:neg-serg/lusty";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neg-pkgs = {
      url = "github:neg-serg/nixos-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.wl.follows = "wl";
      inputs.rsmetrx.follows = "rsmetrx";
    };
    aurora-src = {
      url = "git+ssh://git@github.com/neg-serg/aurora";
      flake = false;
    };
    aurora-plugins-src = {
      url = "github:neg-serg/aurora-plugins";
      flake = false;
    };
    # Vendored Renoise/Redux installers (licensed builds, >100 MB). They cannot
    # live in this repo — GitHub rejects files >100 MB — and moving them inside
    # the tree does not help: the flake source contains tracked files only,
    # while absolute paths are forbidden in pure evaluation. Keep them under
    # $XDG_DATA_HOME (/home/neg/.local/share/nixos-src/renoise on trantor);
    # they arrive as a path input.
    renoise-src = {
      url = "path:/home/neg/.local/share/nixos-src/renoise";
      flake = false;
    };
    nix-maid.url = "git+https://codeberg.org/viperML/nix-maid";
    hyprscratch = {
      url = "github:neg-serg/hyprscratch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pleamar-config = {
      # The pleamar shell as its own flake: scene tree, worker crates, the
      # nix-maid module and the greetd login layer. A `path:` input on the live
      # checkout keeps the deployed links writable (the module's `liveRoot`
      # points at the same directory).
      url = "path:/home/neg/src/pleamar-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsmetrx = {
      url = "github:neg-serg/rsmetrx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tailray = {
      url = "github:NotAShelf/tailray";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steam-config-nix = {
      url = "github:unazikx/steam-config-nix/feat/winetricks";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Out-of-tree MT7927/MT6639 WiFi (mt76/mt7925e) + BT drivers for NixOS
    # (jetm dkms port). WiFi only: BT is handled by the in-tree 6.18 backport.
    # Pinned rev: API rate-limits block unpinned resolution; update with
    # `nix flake lock --update-input mt7927` once the limit clears.
    # REMOVED 2026-10-31: the 7.3 kernel carries mt7925e/MT7925 natively
    # (CONFIG_MT7925E), so the out-of-tree build is no longer needed — see
    # hosts/trantor/hardware.nix and modules/system/kernel/overlay.config (H22).
    # Pin any top-level nixpkgs attribute (pkgs.*) to an exact version from a
    # single flake input (no juggling multiple nixpkgs pins). Enabled via
    # modules/system/multiverse.nix; add pins there.
    # Pinned rev (main, 2026-09-01): unpinned resolution is blocked on this host
    # (api.github.com unreachable); update via nix flake lock --update-input multiverse.
    multiverse.url = "github:fzakaria/nixpkgs-multiverse/4e42650d06172b925d85b134fb924ae6d109cf60";
    # CachyOS-patched kernels (BORE/eevdf schedulers, zen4 CPU tunings) + ZFS
    # module. Deliberately NOT following nixpkgs: upstream warns that overriding
    # its nixpkgs input can mismatch patches and kernel versions.
    # Pinned rev (release branch, 2026-09-01) — same reason as multiverse above.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/594956b9640690cf0079d03d6b3a6a8f380ceea3";
    # nix-cache-pin — rewrites a flake input to the newest revision whose
    # packages all have binary-cache hits (`nix run .#cache-pin-<pin>`, pins in
    # flake/cache-pin.nix). Fork: caniko/nix-cache-pin PR #20 (compromised-cache
    # ban) plus the redirect guard, which upstream does not ship yet. Follows the
    # top-level nixpkgs so the tool builds against the system pin.
    nix-cache-pin = {
      url = "github:neg-serg/nix-cache-pin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.harbor-rs.inputs.nixpkgs.follows = "nixpkgs";
    };
    waylandar = {
      url = "github:samjoshuadud/waylandar/b46d5c348f846ca489071f2d271312ea35c019b4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bootvine = {
      url = "git+https://codeberg.org/wvhulle/bootvine";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [ (inputs.import-tree ./flake/parts) ];
    };
}
