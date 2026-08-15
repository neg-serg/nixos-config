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

*Default:*

```nix
{ }
```

*Declared by:*

- [\<nixpkgs/lib/modules.nix>](https://github.com/NixOS/nixpkgs/blob//lib/modules.nix)

## features.apps.guiAppsFull.enable

Whether to enable enable heavy GUI apps (GIMP, OBS Studio).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.obsidian.enable

Whether to enable enable Obsidian knowledge base app + vault.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.obsidian.autostart.enable

Whether to enable autostart Obsidian at GUI login (systemd user service).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.throne.enable

Whether to enable enable Throne GUI proxy configuration manager.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.winapps.enable

Whether to enable enable WinApps integration (KVM/libvirt Windows VM, RDP bridge).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.apps.winapps.desktopApps

WinApps to generate .desktop files for (e.g. [ “excel” “word” “vscode” ])

*Type:* list of string

*Default:*

```nix
[ ]
```

*Declared by:*

- [/modules/features/apps.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/apps.nix)

## features.cli.broot.enable

Whether to enable enable broot file manager and shell integration.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.cli.yazi.enable

Whether to enable enable yazi terminal file manager.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/cli.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/cli.nix)

## features.dev.enable

Whether to enable enable Dev stack (toolchains, editors, hack tooling).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.ai.enable

Whether to enable enable AI tools (e.g., LM Studio).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.ai.omp.enable

Whether to enable install Oh My Pi (omp) AI coding agent (fork of Pi).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.bpf.enable

Whether to enable enable BPF tracing tools (bpftrace, below).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.cpp.enable

Whether to enable enable C/C++ tooling (gcc/clang, cmake, ninja, lldb).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.haskell.enable

Whether to enable enable Haskell tooling (ghc, cabal, stack, HLS).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.java.enable

Whether to enable enable Java/JVM development tooling (JDK, Maven).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.java.maven

Whether to enable enable Apache Maven build tool.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.iac

Whether to enable enable infrastructure-as-code tooling (Terraform, etc.).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.pkgs.joern

Whether to enable enable Joern code analysis platform.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.python.core

Whether to enable enable core Python development packages.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.python.tools

Whether to enable enable Python tooling (LSP, utilities).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.rust.enable

Whether to enable enable Rust tooling (rustup, rust-analyzer).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.tla.enable

Whether to enable enable TLA+ tooling (toolbox, formatter).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.enable

Whether to enable enable Unreal Engine 5 tooling.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.branch

Branch or tag to sync from the Unreal Engine repository.

*Type:* string

*Default:*

```nix
"5.4"
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.repo

Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).

*Type:* string

*Default:*

```nix
"git@github.com:EpicGames/UnrealEngine.git"
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.root

Checkout directory for Unreal Engine sources. Defaults to “~/games/UnrealEngine”.

*Type:* null or string

*Default:*

```nix
null
```

*Example:*

```nix
"/mnt/storage/UnrealEngine"
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.dev.unreal.useSteamRun

Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.

*Type:* boolean

*Default:*

```nix
true
```

*Declared by:*

- [/modules/features/dev.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/dev.nix)

## features.devSpeed.enable

Whether to enable enable dev-speed mode (trim heavy features for faster eval).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.emulators.extra.enable

Whether to enable enable Extra Emulators (PCSX2, DOSBox, etc.).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.emulators.retroarch.enable

Whether to enable enable RetroArch emulator.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.emulators.retroarch.full

Whether to enable use retroarchFull with extended (unfree) cores.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.excludePkgs

List of package names (pname) to exclude from curated home.packages lists.

*Type:* list of string

*Default:*

```nix
[ ]
```

*Declared by:*

- [/modules/features/core.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/core.nix)

## features.flatpak.builder.enable

Whether to enable enable flatpak-builder.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.fun.enable

Whether to enable enable fun extras (art collections, etc.).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.games.enable

Whether to enable enable Games stack.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.dosemu.enable

Whether to enable enable Dosemu.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.nethack.enable

Whether to enable enable Nethack.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.openmw.enable

Whether to enable enable OpenMW (Morrowind Engine).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.oss.enable

Whether to enable enable OSS Games (SuperTux, Wesnoth, etc.).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.games.steamProxy.enable

Whether to enable route Steam traffic through local SOCKS5 proxy (proxychains LD_PRELOAD).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/games.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/games.nix)

## features.gpg.enable

Whether to enable enable GPG and gpg-agent (creates ~/.gnupg).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.gui.enable

Whether to enable enable GUI stack (wayland/hyprland, quickshell, etc.).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.caelestia-shell.enable

Whether to enable enable Caelestia Desktop Shell (built on Quickshell).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.gtkTheme

GTK theme to apply system-wide.

*Type:* one of “neg-gtk”, “Flight-Dark-GTK”, “Andromeda”, “Flat-Remix-GTK-Blue-Darkest”

*Default:*

```nix
"neg-gtk"
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.hdr.enable

Whether to enable enable HDR support (env vars for DXVK, Gamescope, Wine).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.iconTheme

Icon theme to apply system-wide (GTK + Qt).

*Type:* string

*Default:*

```nix
"kora-pgrey"
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.qt.enable

Whether to enable enable Qt integrations for GUI (qt6ct, hyprland-qt-\*).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.quickshell.enable

Whether to enable enable Quickshell (panel) at login.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.quickshell.flavor

Which quickshell configuration flavor to use.

*Type:* value “default” (singular enum)

*Default:*

```nix
"default"
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.vicinae.enable

Whether to enable enable Vicinae (Wayland app runner + window switcher).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.gui.vicinae.manageConfig

Whether to enable let Nix manage vicinae theme/settings (disable for interactive config).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/gui.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/gui.nix)

## features.hardware.amdgpu.rocm.enable

Whether to enable enable AMDGPU ROCm support.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.hardware.bluetooth.enable

Whether to enable enable Bluetooth support.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.hardware.liquidctl.enable

Whether to enable Enable liquidctl tooling and optional init service for AIO/cooler controllers…

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.hardware.liquidctl.initCommand

Command to run at boot to initialize the cooler (default: initialize all).

*Type:* string

*Default:*

```nix
"/nix/store/r3niipfmlqydhzqzi0pw2wiwbyw059vb-python3.13-liquidctl-1.16.0/bin/liquidctl initialize all"
```

*Example:*

```nix
"/nix/store/r3niipfmlqydhzqzi0pw2wiwbyw059vb-python3.13-liquidctl-1.16.0/bin/liquidctl initialize all --fan-speed 60 --pump-speed 70"
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.hardware.liquidctl.runInit

Whether to run the init command at boot.

*Type:* boolean

*Default:*

```nix
true
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.hardware.usbAutomount.enable

Whether to enable Enable udev-driven USB storage auto-mount via systemd service (mounts under
/mnt/\<label>). .

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.input.kanata.enable

Whether to enable enable Kanata keyboard remapper (requires uinput module).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/hardware.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/hardware.nix)

## features.llm.enable

Whether to enable enable local LLM stack (Ollama, local-ai).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.mail.enable

Whether to enable enable Mail stack (notmuch, isync, vdirsyncer, etc.).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.mail.mbsync.enable

Whether to enable enable mbsync IMAP sync service/timer.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.mail.vdirsyncer.enable

Whether to enable enable Vdirsyncer sync service/timer.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.media.aiUpscale.enable

Whether to enable enable AI upscaling integration for video (mpv).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.content

Tuning/model preference for content type.

*Type:* one of “general”, “anime”

*Default:*

```nix
"general"
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.installShaders

Whether to enable install recommended mpv GLSL shaders (FSRCNNX/SSimSR/Anime4K).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.mode

AI upscale mode: realtime (mpv VapourSynth) or offline (CLI pipeline).

*Type:* one of “realtime”, “offline”

*Default:*

```nix
"realtime"
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.aiUpscale.scale

Upscale factor for realtime path (2 or 4).

*Type:* signed integer

*Default:*

```nix
2
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.apps.enable

Whether to enable enable audio apps (players, tools).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.beets.enable

Whether to enable enable Beets music library manager.

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.beets.mode

Beets runtime mode: native (Nixpkgs) or distrobox (CachyOS container)

*Type:* one of “native”, “distrobox”

*Default:*

```nix
"distrobox"
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.carlaLoopback.enable

Whether to enable enable virtual loopback sink for Carla.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.cider.enable

Whether to enable enable Cider (Apple Music client).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.core.enable

Whether to enable enable audio core (PipeWire routing tools).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.creation.enable

Whether to enable enable audio creation stack (DAW, synths).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.mpd.enable

Whether to enable enable MPD stack (mpd, clients, mpdris2).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.proAudio.enable

Whether to enable enable professional audio tools (REW, OpenSoundMeter, rtcqs).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.spicetify.enable

Whether to enable enable Spicetify (Spotify customization).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.audio.spotify.enable

Whether to enable enable Spotify stack (spotifyd daemon, spotify-tui).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.photo.enable

Whether to enable enable photography workflow (darktable, rawtherapee, testdisk).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.media.webcam.enable

Whether to enable enable virtual webcam support (v4l2loopback).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/media.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/media.nix)

## features.net.awgTunnel.enable

Whether to enable enable AmneziaWG obfuscated WireGuard tunnel (requires amneziawg-dkms).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.bbrv3.enable

Whether to enable enable TCP BBRv3 congestion control (kernel >= 6.18).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.lan-proxy.enable

Whether to enable enable LAN SOCKS5 proxy without auth (0.0.0.0:10809).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.proxy.enable

Whether to enable enable Xray SOCKS5 proxy (127.0.0.1:10808).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.rknDomains.enable

Whether to enable enable RKN domain blocklist fetcher with daily timer.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.tailscale.enable

Whether to enable enable Tailscale mesh VPN and Tailray GUI.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.transparent-proxy.enable

Whether to enable enable transparent proxy (nftables + redsocks -> Xray SOCKS5).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.transparent-tun.enable

Whether to enable enable TUN-based routing for nix traffic (nftables fwmark → custom routing table).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.vpn-scripts.enable

Whether to enable enable VPN helper scripts collection (cdn-proxy, split-router, etc.).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.wifi.enable

Whether to enable enable Wi-Fi stack and management tools (iwd, wavemon, etc.).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.net.zapret2.enable

Whether to enable enable Zapret2 DPI bypass via nfqueue (requires zapret2 package).

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.optimization.enable

Whether to enable Global system optimizations.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/optimization.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/optimization.nix)

## features.secrets.enable

Whether to enable enable secrets tooling (pass, YubiKey helpers).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.system.logTtys.enable

Whether to enable Per-TTY log classification (journalctl viewers on tty8,tty10-tty16).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.auth.enable

Whether to enable AUTH log viewer on tty13 (auth messages).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.crit.enable

Whether to enable CRIT log viewer on tty8 (emerg…crit).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.err.enable

Whether to enable ERR log viewer on tty10 (errors).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.full.enable

Whether to enable FULL log viewer on tty16 (all messages).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.kernel.enable

Whether to enable KERNEL log viewer on tty12 (kernel messages).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.network.enable

Whether to enable NETWORK log viewer on tty15 (network daemons).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.networkUnits

Systemd units to monitor on tty15 (network TTY). Override per-host.

*Type:* list of string

*Default:*

```nix
[
  "NetworkManager.service"
  "sshd.service"
  "nftables.service"
]
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.systemd.enable

Whether to enable SYSTEMD log viewer on tty14 (systemd messages).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.system.logTtys.warn.enable

Whether to enable WARN log viewer on tty11 (warnings).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.text.manipulate.enable

Whether to enable enable text/markup manipulation CLI tools (jq/yq/htmlq).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.notes.enable

Whether to enable enable notes tooling (zk CLI).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.text.read.enable

Whether to enable enable reading stack (CLI/GUI viewers, OCR, Recoll).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/misc.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/misc.nix)

## features.torrent.enable

Whether to enable enable Torrent stack (Transmission, tools, services).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/network.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/network.nix)

## features.virt.docker.enable

Whether to enable enable docker/podman virtualization.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.virt.libvirtd.enable

Whether to enable enable libvirtd (KVM/QEMU) virtualization.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/system.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/system.nix)

## features.web.enable

Whether to enable enable Web stack (browsers + tools).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.chat.enable

Whether to enable enable Telegram chat client (static binary, GTK-free).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.default

Default browser used for XDG handlers, $BROWSER, and integrations.

*Type:* string

*Default:*

```nix
null
```

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.tools.enable

Whether to enable enable web tools (aria2, yt-dlp, misc).

*Type:* boolean

*Default:*

```nix
true
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)

## features.web.vivaldi.enable

Whether to enable enable Vivaldi browser.

*Type:* boolean

*Default:*

```nix
false
```

*Example:*

```nix
true
```

*Declared by:*

- [/modules/features/web.nix](https://github.com/neg-serg/nixos/blob/master/modules/features/web.nix)
