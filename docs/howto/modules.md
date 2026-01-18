## \_module.args

Additional arguments passed to each module in addition to ones like `lib`, `config`, and `pkgs`,
`modulesPath`.

This option is also available to all submodules. Submodules do not inherit args from their parent
module, nor do they provide args to their parent module or sibling submodules. The sole exception to
this is the argument `name` which is provided by parent modules to a submodule and contains the
attribute name the submodule is bound to, or a unique generated name if it is not bound to an
attribute.

Some arguments are already passed by default, of which the following *cannot* be changed with this
option:

- `lib`: The nixpkgs library.

- `config`: The results of all options after merging the values from all modules together.

- `options`: The options declared in all modules.

- `specialArgs`: The `specialArgs` argument passed to `evalModules`.

- All attributes of `specialArgs`

  Whereas option values can generally depend on other option values thanks to laziness, this does
  not apply to `imports`, which must be computed statically before anything else.

  For this reason, callers of the module system can provide `specialArgs` which are available during
  import resolution.

  For NixOS, `specialArgs` includes `modulesPath`, which allows you to import extra modules from the
  nixpkgs package tree without having to somehow make the module aware of the location of the
  `nixpkgs` or NixOS directories.

  ```
  { modulesPath, ... }: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
    ];
  }
  ```

For NixOS, the default value for this option includes at least this argument:

- `pkgs`: The nixpkgs package set according to the `nixpkgs.pkgs` option.

*Type:* lazy attribute set of raw value

*Declared by:*

- [\<nixpkgs/lib/modules.nix>](https://github.com/NixOS/nixpkgs/blob//lib/modules.nix)

## features.allowUnfree.allowed

Final allowlist of unfree package names (overrides preset if explicitly set).

*Type:* list of string

*Default:* `[ ]`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.allowUnfree.extra

Extra unfree package names to allow (in addition to preset).

*Type:* list of string

*Default:* `[ ]`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.allowUnfree.preset

Preset allowlist for unfree packages.

*Type:* one of “desktop”, “headless”

*Default:* `"desktop"`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.apps.hiddify.enable

Whether to enable enable Hiddify VPN client.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.libreoffice.enable

Whether to enable enable LibreOffice (Flatpak).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.obsidian.autostart.enable

Whether to enable autostart Obsidian at GUI login (systemd user service).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.throne.enable

Whether to enable enable Throne GUI proxy configuration manager.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.winapps.enable

Whether to enable enable WinApps integration (KVM/libvirt Windows VM, RDP bridge).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.cli.broot.enable

Whether to enable enable broot file manager and shell integration.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.fastCnf.enable

Whether to enable enable fast zsh command-not-found handler powered by nix-index.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.television.enable

Whether to enable enable television (blazingly fast fuzzy finder).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.tewi.enable

Whether to enable enable tewi tui torrent client configuration.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.yandexCloud.enable

Whether to enable enable Yandex Cloud CLI.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.yazi.enable

Whether to enable enable yazi terminal file manager.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.zcli.enable

Whether to enable install zcli helper for nh-based flake switches.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.zcli.backupFiles

Relative paths under $HOME that zcli should report as pre-existing backups.

*Type:* list of string

*Default:* `[ ]`

*Example:*

```
[
  ".config/mimeapps.list.backup"
]
```

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.zcli.flakePath

Optional override for the flake.nix path if it is not under repoRoot.

*Type:* null or string

*Default:* `null`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.zcli.profile

Profile/hostname passed to nh os switch --hostname.

*Type:* string

*Default:* `"telfir"`

*Example:* `"telfir"`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.zcli.repoRoot

Optional override for the repository root; defaults to the configured neg.repoRoot.

*Type:* null or string

*Default:* `null`

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.dev.enable

Whether to enable enable Dev stack (toolchains, editors, hack tooling).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.ai.enable

Whether to enable enable AI tools (e.g., LM Studio).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.ai.antigravity.enable

Whether to enable install Google Antigravity agentic IDE.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.bpf.enable

Whether to enable enable BPF tracing tools (bpftrace, below).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.cpp.enable

Whether to enable enable C/C++ tooling (gcc/clang, cmake, ninja, lldb).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.emacs.enable

Whether to enable enable Emacs editor with org-babel config.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.core.crawl

Whether to enable enable web crawling tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.core.reverse

Whether to enable enable reverse/disasm helpers.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.core.secrets

Whether to enable enable git secret scanners.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.forensics.analysis

Whether to enable enable reverse/binary analysis tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.forensics.fs

Whether to enable enable filesystem/disk forensics tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.forensics.network

Whether to enable enable network forensics tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.forensics.stego

Whether to enable enable steganography tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.hack.pentest

Whether to enable enable pentest tools.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.haskell.enable

Whether to enable enable Haskell tooling (ghc, cabal, stack, HLS).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.iac.backend

Choose IaC backend: HashiCorp Terraform or OpenTofu (tofu).

*Type:* one of “terraform”, “tofu”

*Default:* `"terraform"`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.enable

Whether to enable enable OpenXR development stack.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.envision.enable

Whether to enable install Envision UI for Monado.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.runtime.enable

Whether to enable install Monado OpenXR runtime.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.runtime.service.enable

Whether to enable run monado-service as a user systemd service (graphical preset).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.runtime.vulkanLayers.enable

Whether to enable install Monado Vulkan layers.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.tools.basaltMonado.enable

Whether to enable install optional basalt-monado tools.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.openxr.tools.motoc.enable

Whether to enable install motoc (Monado Tracking Origin Calibration).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.analyzers

Whether to enable enable analyzers/linters.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.codecount

Whether to enable enable code counting tools.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.formatters

Whether to enable enable CLI/code formatters.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.iac

Whether to enable enable infrastructure-as-code tooling (Terraform, etc.).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.misc

Whether to enable enable misc dev helpers.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.radicle

Whether to enable enable radicle tooling.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.runtime

Whether to enable enable general dev runtimes (node etc.).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.python.core

Whether to enable enable core Python development packages.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.python.tools

Whether to enable enable Python tooling (LSP, utilities).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.rust.enable

Whether to enable enable Rust tooling (rustup, rust-analyzer).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.tla.enable

Whether to enable enable TLA+ tooling (toolbox, formatter).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.enable

Whether to enable enable Unreal Engine 5 tooling.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.branch

Branch or tag to sync from the Unreal Engine repository.

*Type:* string

*Default:* `"5.4"`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.repo

Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).

*Type:* string

*Default:* `"git@github.com:EpicGames/UnrealEngine.git"`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.root

Checkout directory for Unreal Engine sources. Defaults to “~/games/UnrealEngine”.

*Type:* null or string

*Default:* `null`

*Example:* `"/mnt/storage/UnrealEngine"`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.useSteamRun

Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.

*Type:* boolean

*Default:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.devSpeed.enable

Whether to enable enable dev-speed mode (trim heavy features for faster eval).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.emulators.extra.enable

Whether to enable enable Extra Emulators (PCSX2, DOSBox, etc.).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.emulators.retroarch.enable

Whether to enable enable RetroArch emulator.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.emulators.retroarch.full

Whether to enable use retroarchFull with extended (unfree) cores.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.excludePkgs

List of package names (pname) to exclude from curated home.packages lists.

*Type:* list of string

*Default:* `[ ]`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.finance.tws.enable

Whether to enable enable Trader Workstation (IBKR) desktop client.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.fun.enable

Whether to enable enable fun extras (art collections, etc.).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.games.enable

Whether to enable enable Games stack.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.dosemu.enable

Whether to enable enable Dosemu.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.launchers.heroic.enable

Whether to enable enable Heroic Launcher.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.launchers.lutris.enable

Whether to enable enable Lutris.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.launchers.prismlauncher.enable

Whether to enable enable PrismLauncher.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.nethack.enable

Whether to enable enable Nethack.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.openmw.enable

Whether to enable enable OpenMW (Morrowind Engine).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.oss.enable

Whether to enable enable OSS Games (SuperTux, Wesnoth, etc.).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.gpg.enable

Whether to enable enable GPG and gpg-agent (creates ~/.gnupg).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.gui.enable

Whether to enable enable GUI stack (wayland/hyprland, quickshell, etc.).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.hy3.enable

Whether to enable enable the hy3 tiling plugin for Hyprland.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.qt.enable

Whether to enable enable Qt integrations for GUI (qt6ct, hyprland-qt-\*).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.quickshell.enable

Whether to enable enable Quickshell (panel) at login.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.walker.enable

Whether to enable enable Walker application launcher.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.hack.enable

Whether to enable enable Hack/security tooling stack.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.hardware.amdgpu.rocm.enable

Whether to enable enable AMDGPU ROCm support.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.hardware.bluetooth.enable

Whether to enable enable Bluetooth support.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.llm.enable

Whether to enable enable local LLM stack (Ollama, local-ai).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.mail.enable

Whether to enable enable Mail stack (notmuch, isync, vdirsyncer, etc.).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.mail.vdirsyncer.enable

Whether to enable enable Vdirsyncer sync service/timer.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.media.aiUpscale.enable

Whether to enable enable AI upscaling integration for video (mpv).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.content

Tuning/model preference for content type.

*Type:* one of “general”, “anime”

*Default:* `"general"`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.installShaders

Whether to enable install recommended mpv GLSL shaders (FSRCNNX/SSimSR/Anime4K).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.mode

AI upscale mode: realtime (mpv VapourSynth) or offline (CLI pipeline).

*Type:* one of “realtime”, “offline”

*Default:* `"realtime"`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.scale

Upscale factor for realtime path (2 or 4).

*Type:* signed integer

*Default:* `2`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.apps.enable

Whether to enable enable audio apps (players, tools).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.carlaLoopback.enable

Whether to enable enable virtual loopback sink for Carla.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.cider.enable

Whether to enable enable Cider (Apple Music client).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.core.enable

Whether to enable enable audio core (PipeWire routing tools).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.creation.enable

Whether to enable enable audio creation stack (DAW, synths).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.mpd.enable

Whether to enable enable MPD stack (mpd, clients, mpdris2).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.proAudio.enable

Whether to enable enable professional audio tools (REW, OpenSoundMeter, rtcqs).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.spicetify.enable

Whether to enable enable Spicetify (Spotify customization).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.spotify.enable

Whether to enable enable Spotify stack (spotifyd daemon, spotify-tui).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.yandexMusic.enable

Whether to enable enable Yandex Music client.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.photo.enable

Whether to enable enable photography workflow (darktable, rawtherapee, testdisk).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.webcam.enable

Whether to enable enable virtual webcam support (webcamize, v4l2loopback).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.net.tailscale.enable

Whether to enable enable Tailscale mesh VPN and Tailray GUI.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.net.wifi.enable

Whether to enable enable Wi-Fi stack and management tools (iwd, wavemon, etc.).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.profile

Profile preset that adjusts feature defaults: full or lite.

*Type:* one of “full”, “lite”

*Default:* `"full"`

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.secrets.enable

Whether to enable enable secrets tooling (pass, YubiKey helpers).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.espanso.enable

Whether to enable enable espanso text expander.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.manipulate.enable

Whether to enable enable text/markup manipulation CLI tools (jq/yq/htmlq).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.notes.enable

Whether to enable enable notes tooling (zk CLI).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.read.enable

Whether to enable enable reading stack (CLI/GUI viewers, OCR, Recoll).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.tex.enable

Whether to enable enable TeX/LaTeX stack (TexLive full, rubber).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.torrent.enable

Whether to enable enable Torrent stack (Transmission, tools, services).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.torrent.prometheus.enable

Whether to enable enable Prometheus exporter for Transmission (transmission-exporter).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/services.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/services.nix)

## features.web.enable

Whether to enable enable Web stack (browsers + tools).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.addonsFromNUR.enable

Whether to enable install Mozilla addons from NUR packages (heavier eval).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.aria2.service.enable

Whether to enable run aria2 download manager as a user service (graphical preset).

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.brave.enable

Whether to enable enable Brave browser.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.chrome.enable

Whether to enable enable Google Chrome browser.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.default

Default browser used for XDG handlers, $BROWSER, and integrations.


*Default:* `"floorp"`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.edge.enable

Whether to enable enable Microsoft Edge browser.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.firefox.enable

Whether to enable enable Firefox browser.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.floorp.enable

Whether to enable enable Floorp browser.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.librewolf.enable

Whether to enable enable LibreWolf browser.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)



*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.prefs.fastfox.enable

Whether to enable enable FastFox-like perf prefs for Mozilla browsers.

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.tools.enable

Whether to enable enable web tools (aria2, yt-dlp, misc).

*Type:* boolean

*Default:* `true`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.vivaldi.enable

Whether to enable enable Vivaldi browser.

*Type:* boolean

*Default:* `false`

*Example:* `true`

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)
