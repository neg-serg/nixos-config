# codebase-cleanup - Work Plan

## TL;DR (For humans)

**What you'll get:** Массовая чистка NixOS-конфигурации: удаление мёртвого кода, упрощение повторяющихся паттернов, миграция на современные Nix API (`lib.getExe`, `lib.generators`, `lib.types.submoduleWith`, `lib.optionalAttrs`).

**Effort:** XL
**Risk:** Low

## Todos

### ✅ Wave 1: Dead code & quick cleanups
- [x] W1.1: Remove dead packages in aur-ported.nix (oports, snixembed, tanin)
- [x] W1.2: Fix post-boot.nix — remove mkIf true no-op + unused arg
- [x] W1.3: Remove commented-out blocks (cli/tools.nix, services.nix Docker, networking.nix old LAN, filesystems.nix swap)
- [x] W1.4: Remove dead imapnotify service in mail.nix
- [x] W1.5: Fix opts.nix — optionalAttrs вместо if-then-else
- [x] W1.6: Fix net/pkgs.nix — triple optionals → single mkIf block
- [x] W1.7: Fix xdg.nix — collapse mkdir commands
- [x] W1.8: lib.getExe migration batch 1 (system/net/*, boot, irqbalance, firewall, security)
- [x] W1.9: lib.getExe migration batch 3 (hosts/odin/services.nix)

### ✅ Wave 2: Medium simplifications
- [x] W2.1: features/default.nix — assertions через assertParent helper
- [x] W2.2: monitoring.nix — lib.generators вместо самописного mkBtopConf
- [x] W2.3: services-manual.nix — generators для aria2 config
- [x] W2.4: Unify mkBool — удалить дубликаты из features/system.nix, system/virt.nix, flatpak/pkgs.nix
- [x] W2.5: submoduleWith + types.attrs fix в profiles/services.nix

### 🔄 Wave 3: In progress
- [ ] W3.1: lib.getExe migration batch 2 (log-ttys.nix + user modules)

### 📋 Wave 4: More complex / optional
- [ ] W4.1: log-ttys.nix data-driven refactor (157→50 lines)
- [ ] W4.2: flake.nix — lib.fileset для source filtering
- [ ] W4.3: environment.nix — genAttrs для makePluginPath
- [ ] W4.4: Kernel params flattten (marginal, skip if clear)
