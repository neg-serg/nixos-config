# log-ttys — Work Plan

## TL;DR (For humans)

**Что получите:** 8 TTY с разделёнными по категориям логами. Переключение — `Ctrl+Alt+F8`, `F10`–`F16`. Текущий «шум» с `ForwardToConsole=yes` исчезнет с tty1-6.

**Почему systemd-сервисы, а не syslog-ng:** journald не умеет фильтровать `ForwardToConsole`. Альтернатива syslog-ng добавляет 80+ MB в closure. Systemd-сервисы с `journalctl -f` — zero новых пакетов, 8 лёгких процессов (<40 MB RAM суммарно).

**Что НЕ делает:** Не трогает tty1-6 (консоли входа). tty9 оставлен под debug-shell (аварийный root-доступ). Не меняет `Storage=persistent`. Не добавляет пакетов в closure.

**Усилие:** ~70 строк нового модуля + 5 строк правок + 1 новый файл feature-флагов. 7 коммитов.

**Риски:**
- `debug-shell` на tty9 — план сознательно пропускает tty9, сдвигая логи на tty10+
- Сетевые юниты хост-специфичны — список вынесен в опцию `features.system.logTtys.networkUnits`
- При пустом `networkUnits` сетевой TTY-сервис не создаётся (защита от битого `journalctl`)
- При `quietBoot` сервисы всё равно запускаются (можно отключить флагом)

**Ключевые решения:**
- Комбинированная классификация: приоритет + подсистемы
- 8 TTY: tty8, tty10–tty16 (tty9 — debug-shell)
- Формат: `journalctl -o short-monotonic` (компактно, с метками времени)
- Feature-флаги в отдельном файле `modules/features/system.nix`

## Scope

### In scope
- Новый файл feature-флагов: `modules/features/system.nix`
- Новый модуль: `modules/system/log-ttys.nix`
- 8 systemd-сервисов (имена без шаблонного `@`): `log-crit`, `log-err`, `log-warn`, `log-kernel`, `log-auth`, `log-systemd`, `log-network`, `log-full`
- Feature-флаги: `features.system.logTtys.enable` + индивидуальные `features.system.logTtys.<category>.enable` + `features.system.logTtys.networkUnits`
- Удаление `ForwardToConsole=yes` и `MaxLevelConsole=info` из `modules/system/systemd/default.nix`
- Добавление импорта `./system.nix` в `modules/features/default.nix`
- Добавление импорта `./log-ttys.nix` в `modules/system/default.nix`

### Out of scope
- syslog-ng / rsyslog
- Изменение формата вывода существующих юнитов
- Изменение `Storage=persistent` или retention-политик journald
- Переключение TTY для входа (tty1-6 не трогаем)
- Изменение `debug-shell` на tty9 (остаётся как есть)
- Интеграция с plymouth (отключён на данном хосте)

## Verification strategy

**Подход:** Tests-after — проверка после развёртывания: `systemctl is-active` для каждого сервиса + ручная QA переключением на каждый TTY.

**QA на каждый todo:**
- Happy: сервис `active`, на целевом TTY виден поток логов
- Failure: при выключенном флаге сервис не создаётся; при пустом `networkUnits` сетевой сервис отсутствует

## Execution strategy

**Порядок — последовательно, 7 коммитов:**
1. Feature-флаги в новом `modules/features/system.nix` + импорт в `features/default.nix`
2. Новый модуль `log-ttys.nix` (8 сервисов)
3. Импорт модуля в `system/default.nix`
4. Удаление `ForwardToConsole` из `systemd/default.nix`
5. Настройка `networkUnits` для odin (опционально)
6. Ручная QA — все 8 TTY
7. `just check` + верификация closure

**Параллелизм:** Коммиты 1-4 — в одном PR, 5 — host-specific, 6-7 — финальные.

## Todos

### Wave 1: Feature flags

1. [x] **`modules/features/system.nix`: Create file with `features.system.logTtys` option tree**
   **References:** `modules/features/optimization.nix:1-21` (pattern: `lib.mkEnableOption` + `lib.mkOption`), `modules/core/neg.nix:19` (`mkBool` signature: `mkBool desc default`), `modules/features/default.nix:1-22` (imports list)
   **Details:**
   - Create new file `modules/features/system.nix` with:
     ```nix
     { lib, config, ... }:
     let
       cfg = config.features.system.logTtys;
       mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
     in
     {
       options.features.system.logTtys = {
         enable = lib.mkEnableOption "Per-TTY log classification (journalctl viewers on tty8,tty10-tty16)";
         crit.enable = mkBool "CRIT log viewer on tty8 (emerg..crit)" true;
         err.enable = mkBool "ERR log viewer on tty10 (errors)" true;
         warn.enable = mkBool "WARN log viewer on tty11 (warnings)" true;
         kernel.enable = mkBool "KERNEL log viewer on tty12 (kernel messages)" true;
         auth.enable = mkBool "AUTH log viewer on tty13 (auth messages)" true;
         systemd.enable = mkBool "SYSTEMD log viewer on tty14 (systemd messages)" true;
         network.enable = mkBool "NETWORK log viewer on tty15 (network daemons)" true;
         full.enable = mkBool "FULL log viewer on tty16 (all messages)" true;
         networkUnits = lib.mkOption {
           type = lib.types.listOf lib.types.str;
           default = [ "NetworkManager.service" "sshd.service" "tailscaled.service" "nftables.service" ];
           description = "Systemd units to monitor on tty15 (network TTY). Override per-host.";
         };
       };
     }
     ```
   - `mkBool` defined locally (avoids dependency on `_module.args.mkBool` — self-contained)
   **QA happy:** `nix eval .#nixosConfigurations.odin.config.features.system.logTtys.enable` → `true`; `...crit.enable` → `true`
   **QA failure:** `features.system.logTtys.enable = false` → все дочерние `*.enable` форсируются в `false` (через `mkIf` в модуле)
   **Commit:** `[system/log-ttys] Add feature flags in modules/features/system.nix`

2. [x] **`modules/features/default.nix`: Import `./system.nix`**
   **References:** `modules/features/default.nix:8-22` (existing imports list)
   **Details:** Add `./system.nix` to the imports list, alphabetically after `./skwd.nix` (or before it if alphabetically earlier). Ensure `nixos-rebuild build` succeeds.
   **QA happy:** `nix eval .#nixosConfigurations.odin.config.features.system.logTtys.enable` returns `true`
   **QA failure:** Remove the import line, verify `features.system` is undefined → error
   **Commit:** `[system/log-ttys] Wire system.nix feature flags into features/default.nix`

### Wave 2: Core module

3. [x] **`modules/system/log-ttys.nix`: Create module with 8 systemd services**
   **References:** `modules/system/systemd/default.nix` (existing journald config), `modules/system/boot.nix` (module structure pattern), systemd.service(5) man page
   **Details — service template:**
   ```nix
   { lib, config, pkgs, ... }:
   let
     inherit (lib) mkIf mkMerge concatStringsSep;
     cfg = config.features.system.logTtys;
   in
   {
     config = mkIf cfg.enable (mkMerge [
       # Each service: plain name (no @ template), hardcoded TTYPath + filter
       (mkIf cfg.crit.enable {
         systemd.services.log-crit = {
           description = "Journal viewer: emerg..crit on tty8";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 2 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty8";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.err.enable {
         systemd.services.log-err = {
           description = "Journal viewer: errors on tty10";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 3 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty10";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.warn.enable {
         systemd.services.log-warn = {
           description = "Journal viewer: warnings on tty11";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 4 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty11";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.kernel.enable {
         systemd.services.log-kernel = {
           description = "Journal viewer: kernel messages on tty12";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f _TRANSPORT=kernel -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty12";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.auth.enable {
         systemd.services.log-auth = {
           description = "Journal viewer: auth messages on tty13";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f SYSLOG_FACILITY=4 SYSLOG_FACILITY=10 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty13";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.systemd.enable {
         systemd.services.log-systemd = {
           description = "Journal viewer: systemd messages on tty14";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             # `_PID=1` = systemd-pid1 messages (unit lifecycle, targets, failures)
             ExecStart = "${pkgs.systemd}/bin/journalctl -f _PID=1 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty14";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.network.enable {
         systemd.services.log-network = mkIf (cfg.networkUnits != []) {
           description = "Journal viewer: network daemons on tty15";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = concatStringsSep " " (
               [ "${pkgs.systemd}/bin/journalctl" "-f" "-o" "short-monotonic" ]
               ++ map (u: "-u ${u}") cfg.networkUnits
             );
             StandardOutput = "tty";
             TTYPath = "/dev/tty15";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
       (mkIf cfg.full.enable {
         systemd.services.log-full = {
           description = "Journal viewer: all messages on tty16";
           after = [ "systemd-journald.service" ];
           requires = [ "systemd-journald.service" ];
           serviceConfig = {
             ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 7 -o short-monotonic";
             StandardOutput = "tty";
             TTYPath = "/dev/tty16";
             TTYReset = true;
             Restart = "always";
             RestartSec = 5;
             StartLimitIntervalSec = 30;
             StartLimitBurst = 5;
           };
           wantedBy = [ "multi-user.target" ];
         };
       })
     ]);
   }
   ```
   **Acceptance:** `nixos-rebuild build` succeeds. `systemctl list-units 'log-*'` shows 8 services when enabled; 0 when disabled.
   **QA happy:** `systemctl status log-crit` → `active (running)`; `systemctl status log-network` → `active` (если `networkUnits` не пуст)
   **QA failure:** `features.system.logTtys.enable = false` → `systemctl list-units 'log-*'` returns nothing. `networkUnits = []` → `log-network` service absent.
   **Commit:** `[system/log-ttys] Add journalctl TTY multiplexer module (8 services)`

### Wave 3: Wiring

4. [x] **`modules/system/default.nix`: Add import for log-ttys module**
   **References:** `modules/system/default.nix:1-25` (existing imports list)
   **Details:** Add `./log-ttys.nix` to the imports list, alphabetically between `./irqbalance.nix` (line 13) and `./oomd.nix` (line 14).
   **QA happy:** `nix eval .#nixosConfigurations.odin.config.systemd.services.log-crit` returns service definition
   **QA failure:** Remove the import line, verify `log-crit` is absent from eval
   **Commit:** `[system/log-ttys] Wire log-ttys module into system imports`

5. [x] **`modules/system/systemd/default.nix`: Remove ForwardToConsole/MaxLevelConsole**
   **References:** `modules/system/systemd/default.nix:17-29`
   **Details:** Remove `ForwardToConsole=yes` (line 19) and `MaxLevelConsole=info` (line 21) from `services.journald.extraConfig`. Leave everything else intact (`Storage=persistent`, rate limits, rotation). Add a comment: `# Console forwarding is now handled by modules/system/log-ttys.nix (8 per-category TTY viewers)`.
   **QA happy:** `journalctl -b -u systemd-journald --no-pager | grep -i 'forward.*console'` — no matches after rebuild
   **QA failure:** Verify journald starts without ForwardToConsole (`systemctl status systemd-journald` → active)
   **Commit:** `[system/journald] Disable ForwardToConsole — superseded by log-ttys module`

### Wave 4: Host activation + QA

6. [x] **`hosts/odin/default.nix`: Optionally customize networkUnits for odin**
   **References:** `hosts/odin/networking.nix`, `hosts/odin/services.nix`, `hosts/odin/default.nix`
   **Details:** Run `systemctl list-units --type=service --state=running | grep -iE 'net|ssh|tailscale|nft|iwd|dns|proxy|vpn|wg|wireguard'` to discover active network daemons. If the default list misses odin-specific units (e.g., odin uses `systemd-networkd`, not `NetworkManager`), override: `features.system.logTtys.networkUnits = [ "systemd-networkd.service" ... ]`.
   **QA happy:** `Ctrl+Alt+F15` shows log lines from all running network daemons
   **QA failure:** Stop a network service → stop message appears on tty15 within 2 seconds
   **Commit:** `[hosts/odin] Customize log-ttys networkUnits for odin host`

7. [x] **Manual QA: verify all 8 TTYs show logs**
   **References:** Plan TTY mapping table below
   **Details:** After `nixos-rebuild switch`, verify each TTY:

   | TTY | Key | Тест |
   |-----|-----|------|
   | tty8 | CRIT | `echo "TEST_CRIT" \| systemd-cat -p emerg` |
   | tty10 | ERR | `echo "TEST_ERR" \| systemd-cat -p err` |
   | tty11 | WARN | `echo "TEST_WARN" \| systemd-cat -p warning` |
   | tty12 | KERN | Проверить непрерывный dmesg-поток |
   | tty13 | AUTH | `sudo -k; sudo echo test` |
   | tty14 | SYSD | `systemctl daemon-reload` → сообщения PID 1 |
   | tty15 | NET | Перезапустить NetworkManager или аналог |
   | tty16 | FULL | Любое тестовое сообщение |

   **QA happy:** Все 8 TTY показывают логи; тестовые сообщения появляются в течение 2 секунд
   **QA failure:** Любой TTY пуст → `systemctl status log-<name>`, проверить корректность фильтра `journalctl`
   **Commit:** `[qa] Verify log-ttys output on all 8 TTYs`

## Final verification wave

После всех коммитов:
F1. [x] **Plan compliance:** Сравнить финальное состояние файлов с планом — все файлы созданы/изменены согласно списку
F2. [x] **Code quality:** `just check` (treefmt + statix) проходит без ошибок
F3. [x] **Real manual QA:** Переключиться на каждый TTY (F8, F10-F16), убедиться что логи идут. tty9 проверить — debug-shell работает.
F4. [x] **Scope fidelity:** tty1-6 не затронуты, `ForwardToConsole` удалён, `nix path-info -rSh` показывает ноль новых пакетов

## Commit strategy

Префиксы: `[system/log-ttys]`, `[system/journald]`, `[hosts/odin]`, `[qa]`. Порядок:

1. `[system/log-ttys] Add feature flags in modules/features/system.nix`
2. `[system/log-ttys] Wire system.nix feature flags into features/default.nix`
3. `[system/log-ttys] Add journalctl TTY multiplexer module (8 services)`
4. `[system/log-ttys] Wire log-ttys module into system imports`
5. `[system/journald] Disable ForwardToConsole — superseded by log-ttys module`
6. `[hosts/odin] Customize log-ttys networkUnits for odin host`
7. `[qa] Verify log-ttys output on all 8 TTYs`

## Success criteria

1. `ForwardToConsole=yes` удалён — tty1 больше не засоряется логами
2. `Ctrl+Alt+F8` → emerg..crit (уровни 0-2)
3. `Ctrl+Alt+F10` → ошибки (уровень 3)
4. `Ctrl+Alt+F11` → предупреждения (уровень 4)
5. `Ctrl+Alt+F12` → сообщения ядра (`_TRANSPORT=kernel`)
6. `Ctrl+Alt+F13` → аутентификация (facility 4 + 10)
7. `Ctrl+Alt+F14` → systemd (PID 1 — unit lifecycle, targets, failures)
8. `Ctrl+Alt+F15` → сетевые демоны (настраиваемый список юнитов)
9. `Ctrl+Alt+F16` → полный поток (все уровни)
10. Каждый TTY отключается индивидуальным флагом
11. `nixos-rebuild build` без ошибок
12. Ноль новых пакетов в closure (`nix path-info -rSh`)
