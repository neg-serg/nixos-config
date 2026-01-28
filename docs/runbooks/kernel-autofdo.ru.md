# Руководство по оптимизации ядра с AutoFDO

Это руководство описывает процесс оптимизации ядра Linux с использованием AutoFDO
(Auto-Feedback-Directed Optimization). Эта техника позволяет собрать ядро, оптимизированное под ваши
конкретные задачи, используя профиль, собранный на реальной системе.

## Требования

1. **Ядро, собранное Clang**: AutoFDO требует использования Clang/LLVM.
1. **Поддержка Perf**: Ваш процессор должен поддерживать необходимые счетчики PMU (LBR на Intel,
   BRS/amd_lbr_v2 на AMD).

## Рабочий процесс (Workflow)

### 1. Подготовка (Базовая сборка)

Сначала нужно собрать ядро с включенной поддержкой AutoFDO, но без профиля. Это нужно для того,
чтобы структура ядра соответствовала той, на которой будет собираться профиль.

В конфиге хоста (например, `hosts/telfir/hardware.nix`):

```nix
boot.kernel.autofdo.enable = true;
# boot.kernel.autofdo.profile = null; # Убедиться, что null
```

Примените конфигурацию и перезагрузитесь в новое ядро.

### 2. Профилирование (Сбор данных)

Запустите нагрузку, под которую вы хотите оптимизировать систему (например, компиляция большого
проекта, бенчмарк или просто обычная работа), и запустите `perf` для записи.

**Важно**: Параметр `-c` (count) должен быть простым числом (например, 500009), чтобы избежать
предвзятости выборки (lockstep sampling).

#### Intel (с поддержкой LBR)

```bash
perf record -b -e BR_INST_RETIRED.NEAR_TAKEN:k -a -N -c 500009 -o perf.data -- sleep 120
```

(Замените `sleep 120` на вашу команду нагрузки или просто дайте поработать некоторое время)

#### AMD (Zen3 с BRS / Zen4)

Проверка поддержки: `grep -E "brs|amd_lbr_v2" /proc/cpuinfo`

```bash
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o perf.data -- sleep 120
```

### 3. Генерация профиля

Сконвертируйте сырой файл `perf.data` в профиль AutoFDO, используя `create_llvm_prof` (из пакета
`autofdo`) или `llvm-profgen` (из LLVM).

Вам понадобится файл `vmlinux`, соответствующий **текущему** запущенному ядру. В NixOS он часто
находится по пути `/run/current-system/kernel/vmlinux` (если он не сжат), или его нужно достать из
деривации ядра. Важно: для корректной работы AutoFDO нужен `vmlinux` с debug info.

```bash
nix-shell -p autofdo
create_llvm_prof --binary=/run/current-system/kernel/vmlinux --profile=perf.data --format=extbinary --out=kernel.afdo
```

*Примечание: Если `/run/current-system/kernel/vmlinux` — это сжатый bzImage или стрипнутый бинарник,
возможно, придется найти оригинальный `vmlinux` в `/nix/store/...-linux-...-dev/` или аналогичном
месте.*

### 4. Оптимизированная сборка

Переместите созданный `kernel.afdo` в репозиторий конфига (например, в
`files/profiles/kernel.afdo`).

Обновите конфигурацию хоста:

```nix
boot.kernel.autofdo.enable = true;
boot.kernel.autofdo.profile = ./path/to/kernel.afdo; # например, ../../files/profiles/kernel.afdo
```

Пересоберите систему:

```bash
sudo nixos-rebuild switch --flake .#telfir
```

Новое ядро будет собрано с применением PGO-оптимизаций под ваш профиль.
