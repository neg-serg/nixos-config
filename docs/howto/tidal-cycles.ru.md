# TidalCycles на NixOS (odin)

## Архитектура

```mermaid
flowchart LR
    A["Вы в nvim<br/>.tidal файл"] -->|"Alt+Enter"| B["GHCi<br/>(tidal-ghci)"]
    B -->|"OSC UDP :57120"| C["sclang<br/>(SuperDirt)"]
    C -->|"JACK"| D["PipeWire<br/>(квант 128, 48kHz)"]
    D -->|"ALSA"| E["RME HDSPe AIO Pro"]
    C --> F["Dirt-Samples<br/>~170MB wav"]
```

| Слой          | Что                                        | Порт                         |
| ------------- | ------------------------------------------ | ---------------------------- |
| TidalCycles   | Haskell DSL, паттерны ритма/звука          | отправляет OSC на :57120     |
| tidal-ghci    | GHCi с предзагруженным Tidal               | —                            |
| SuperDirt     | SuperCollider-синтезатор, загружает сэмплы | слушает OSC :57120           |
| scsynth       | Аудиосервер SuperCollider                  | OSC :57110, аудио через JACK |
| PipeWire JACK | Низколатентная аудиоподсистема             | квант 128 (2.6ms)            |

## Быстрый старт

```bash
# Каждый раз:
just tidal-start    # запускает SC сервер + SuperDirt (~0.2с до готовности OSC, ~2с до звука)
just tidal          # открывает nvim для кодинга (создаёт ~/src/music/tidal при первом запуске)
```

В nvim:

- `Ctrl+Enter` — запустить GHCi
- Написать паттерн: `d1 $ sound "bd sn"`
- `Alt+Enter` — отправить строку в Tidal
- Услышать kick и snare — всё работает.

Остановка: `Ctrl+Shift+Enter` в nvim, или `just tidal-stop`.

## Клавиши в nvim

| Клавиша            | Действие                    | Контекст        |
| ------------------ | --------------------------- | --------------- |
| `Ctrl+Enter`       | Запустить Tidal + SuperDirt | `.tidal` файл   |
| `Ctrl+Shift+Enter` | Остановить Tidal            | `.tidal` файл   |
| `Alt+Enter`        | Отправить строку в Tidal    | `.tidal` файл   |
| `Ctrl+Enter`       | Запустить GHCi              | из `just tidal` |

## Как это устроено (детали реализации)

### Компоненты

1. **`tidal-ghci`** — враппер `/run/current-system/sw/bin/tidal-ghci`. Запускает GHCi с пакетом
   Tidal, использует `BootTidal.hs` для автоимпорта.
1. **`just tidal-start`** — пайплайн `echo 'команды' | sclang -l startup.scd`, который запускает
   SuperDirt мгновенно.
1. **`sclang -l ~/.config/SuperCollider/superdirt_startup.scd`** — загружает сервер SC с 1M буферов,
   256 wire buffers, 64K нод.
1. **PipeWire JACK** — библиотека `libjack.so` из `pkgs.pipewire.jack` подменяет оригинальный JACK,
   направляя аудио в PipeWire. Квант 128 на 48kHz даёт задержку ~2.6ms.
1. **Dirt-Samples** — Nix-деривация `pkgs.neg.dirt-samples` (~170MB); startup-скрипт указывает
   `~dirt.loadSoundFiles` явный путь в nix store (никакой зависимости от `resolveRelative`/CWD).
1. **SuperDirt и Vowel** — nix-пакеты `pkgs.neg.superdirt` и `pkgs.neg.vowel`, симлинки в
   `~/.local/share/SuperCollider/Extensions/` (наравне с SC3plugins). Ручная установка quark'а через
   `install-superdirt-quark` больше не нужна.
1. **Свои сэмплы** — папка `~/src/music/tidal/samples/`: любая вложенная папка с wav становится
   звуком (имя папки = имя звука). Создаётся `just tidal-start` автоматически.

### Почему запуск мгновенный (0.2с)

Секрет в пайплайне:

```bash
(echo 'SuperDirt-команды') | sclang -l superdirt_startup.scd
```

`sclang` немедленно читает команды из stdin. `s.waitForBoot` в стартовом скрипте запускает
аудиосервер асинхронно. OSC-порт 57120 открывается мгновенно, аудио становится доступно через ~2
секунды. Никаких фиксированных sleep'ов.

## Паттерны Tidal: шпаргалка

### Звуки

```haskell
-- Простые ритмы
d1 $ sound "bd sn bd sn"       -- бочка, рабочий, бочка, рабочий
d2 $ sound "hh*4"              -- хай-хэт 4 удара за цикл
d3 $ sound "arpy cp"           -- арпеджио + клэп

-- Субпаттерны (скобки)
d1 $ sound "bd [sn cp] bd"     -- sn и cp одновременно
d1 $ sound "[bd sn, hh cp]"    -- выбор случайного из каждой пары

-- Евклидовы ритмы
d1 $ sound "bd(3,8)"           -- 3 удара на 8 шагов
d1 $ sound "bd(5,8)"           -- 5 ударов на 8 шагов
```

### Структура (время)

```haskell
-- Разная скорость
d1 $ fast 2 $ sound "bd sn"    -- вдвое быстрее
d1 $ slow 3 $ sound "bd sn"    -- втрое медленнее
d1 $ sound "bd sn" # speed 2   -- скорость семпла (питч)

-- Полиритмия
d1 $ sound "bd(3,8)"
d2 $ sound "hh(5,8)"           -- 3 против 5

-- Свинг
d1 $ swingBy (1/3) 4 $ sound "bd sn:2 hh*3"
```

### Эффекты

```haskell
-- Амплитуда и панорама
d1 $ sound "bd" # gain 1.2 # pan 0.5

-- Реверберация и задержка
d1 $ sound "arpy" # room 0.5 # size 0.8
d1 $ sound "arpy" # delay 0.5 # delaytime (1/3) # delayfeedback 0.7

-- Фильтры
d1 $ sound "bass" # lpf 400 # lpq 0.3      -- low-pass
d1 $ sound "bass" # hpf 200 # hpq 0.5      -- high-pass
d1 $ sound "hh" # bandf 1000 # bandq 0.7   -- band-pass

-- Дробилка (биткрашер)
d1 $ sound "bd" # crush 4

-- Дисторшн
d1 $ sound "bass" # shape 0.7

-- Кольцевая модуляция
d1 $ sound "arpy" # ring 0.5 # ringf 440

-- Огибающая
d1 $ sound "bd" # attack 0.1 # release 0.3 # cutoff 800
```

### Трансформации паттернов

```haskell
-- Реверсирование
d1 $ rev $ sound "bd sn"

-- Смещение во времени
d1 $ 0.25 <~ sound "bd sn"    -- сдвиг на 1/4 цикла

-- Повторение (статтер)
d1 $ stut 4 0.2 0.5 $ sound "bd"   -- 4 повтора с интервалом 0.2

-- Палиндром
d1 $ palindrome $ sound "bd sn hh"

-- Случайный порядок
d1 $ scramble 4 $ sound "bd sn cp hh"

-- Накопление
d1 $ iter 4 $ sound "bd sn hh"     -- сдвигать стартовую точку
```

### Тональные паттерны

```haskell
-- Ноты
d1 $ note "c d e f g a b" # sound "superpiano"

-- Арпеджио аккордов
d1 $ note (arp "up" "c'maj") # sound "superpiano"

-- Масштабы
d1 $ note (scale "minor" "c4") # sound "superpiano"

-- Глиссандо
d1 $ note "c e" # slide 0.5 # sound "superpiano"
```

### Случайность

```haskell
-- Случайный выбор
d1 $ sound (choose ["bd", "sn", "hh"])

-- Случайное число
d1 $ sound "bd" # gain (rand * 1.5)

-- Перемешивание каждые N циклов
d1 $ sometimes (fast 2) $ sound "bd sn"

-- С вероятностью
d1 $ often (|+| gain 0.3) $ sound "bd sn"

-- Редко
d1 $ rarely (rev) $ sound "bd sn"
```

## Аудиомаршрутизация

```bash
# Посмотреть граф PipeWire
just tidal-rt          # watch pw-top

# Патчбей (соединить SuperDirt с выходами)
just tidal-patch       # pw-audioshare — GUI матрица

# Ручная коммутация
pw-link SuperDirt:out_0 "RME AIO Pro:playback_FL"
pw-link SuperDirt:out_1 "RME AIO Pro:playback_FR"
```

SuperDirt создаёт 12 орбит (моно-каналов). По умолчанию они микшируются в стереовыход.

## Запись

```bash
# Запись выхода SuperDirt в ~/src/music/tidal/recordings/ (имя с таймстампом)
just tidal-record

# Или вручную, в текущую директорию
pw-record --target $(pw-link -o | grep SuperDirt | head -1 | awk '{print $1}') recording.wav

# Или запись системного выхода
pw-record recording.wav
```

## Свои сэмплы

Любую папку с wav-файлами клади в `~/src/music/tidal/samples/` — имя папки станет именем звука:

```bash
mkdir -p ~/src/music/tidal/samples/mykit
cp kick.wav snare.wav ~/src/music/tidal/samples/mykit/
```

```haskell
d1 $ sound "mykit"     -- или "mykick" / "mysnare" (имена файлов без расширения)
```

Новые папки подхватываются после перезапуска движка (`just tidal-stop && just tidal-start`) или при
старте. Стандартный банк Dirt-Samples (218 звуков) загружается всегда.

## MIDI

`tidal-midi` временно отключён (сломан в nixpkgs). Когда починят:

```haskell
import Sound.Tidal.MIDI.Output
midi <- midiname "your-device"
d1 $ midi $ note "c d e f" # sound "midi"
```

## OSC во внешние синтезаторы

Параметры OSC (`pF`, `pI`, `pS`, …) доступны из `Sound.Tidal.Boot` без дополнительных импортов. Для
управления внешним синтезатором (например, через sclang/другой OSC-приёмник):

```haskell
d1 $ sound "bd" # pF "myParam" 0.5
```

## Устранение неполадок

### Нет звука

1. Проверить, что SuperDirt запущен: `ss -tuln | grep 57120` должен показать `0.0.0.0:57120`
1. Проверить, что scsynth запущен: `ss -tuln | grep 57110`
1. Проверить цепочку OSC: `tidal-ghci` должен отправлять на `localhost:57120`
1. Проверить аудиоподключения: `pw-link -l | grep SuperDirt`
1. Проверить громкость: в паттерне `# gain 1.5`, в системе `pwvucontrol`

### Потрескивания / xruns

1. Увеличить PipeWire квант: создать `~/.config/pipewire/pipewire.conf.d/99-tidal.conf`:
   ```
   context.properties = { default.clock.quantum = 512 }
   ```
1. Проверить загрузку CPU: `pw-top`
1. Закрыть тяжёлые приложения (браузер, компиляция)
1. Проверить `threadirqs` в параметрах ядра: `cat /proc/cmdline | grep threadirqs`

### SuperDirt не видит сэмплы

```bash
# Стандартный банк (nix store, путь задан в superdirt_startup.scd)
ls /run/current-system/sw/share/ 2>/dev/null | grep -i dirt  # или:
nix path-info /nix/store/*dirt-samples*/share/Dirt-Samples | head -1

# Свои сэмплы
ls ~/src/music/tidal/samples/
```

Если стандартные сэмплы не загружаются — проверить, что startup-скрипт
(`~/.config/SuperCollider/superdirt_startup.scd`) указывает на актуальный nix store путь
`pkgs.neg.dirt-samples` (путь генерируется при пересборке).

### "ghci not found"

Убедиться, что `tidal-ghci` в PATH:

```bash
which tidal-ghci
# Если нет — nixos-rebuild не завершён: sudo nixos-rebuild switch --flake /etc/nixos#odin
```

`LD_LIBRARY_PATH` должен содержать путь к PipeWire JACK. После перезахода в систему выставляется
автоматически. Проверить: `echo $LD_LIBRARY_PATH | grep pipewire`.

### SuperDirt запускается, но scsynth падает

Проверить, что PipeWire JACK запущен:

```bash
pw-cli ls Module | grep jack
# Должен показать: libpipewire-module-jackdbus-detect
```

Если нет: `systemctl --user restart pipewire`

### "No more buffer numbers" при загрузке сэмплов

Слишком много сэмплов для заданного лимита. Увеличить в
`~/.config/SuperCollider/superdirt_startup.scd`:

```
s.options.numBuffers = 1024 * 2048;  -- 2M буферов
```

Затем `sudo nixos-rebuild switch`.

## Советы

### Сохранение сессий

`.tidal` файлы — это обычный код. Держите их в `~/src/music/tidal/` (...). Рекомендую git.

### Быстрый перезапуск

Если паттерн «залип» (не обновляется):

- `Ctrl+Shift+Enter` — убить GHCi
- `Ctrl+Enter` — перезапустить
- Заново отправить паттерны

### Несколько окон

Держите три терминала:

1. Окно с `just tidal-start` (логи SC)
1. Окно с `just tidal` (nvim)
1. Окно с `just tidal-rt` (мониторинг аудио)

### Автозапуск при логине

Добавить в автозапуск (через quickshell или systemd user service):

```bash
systemctl --user enable --now tidal.service
```

(Требуется создать unit-файл.)

## Файлы

| Путь                                                      | Назначение                           |
| --------------------------------------------------------- | ------------------------------------ |
| `~/.config/SuperCollider/superdirt_startup.scd`           | Конфигурация SC сервера (1M буферов) |
| `~/.config/SuperCollider/sclang_conf.yaml`                | Конфиг classpath (nix-maid)          |
| `~/.config/SuperCollider/boot_noop.scd`                   | Минимальная загрузка сервера         |
| `~/.config/tidal/BootTidal.hs`                            | Импорты и настройки GHCi             |
| `~/.local/share/SuperCollider/Extensions/SuperDirt/`      | Классы SuperDirt (nix-пакет)         |
| `~/.local/share/SuperCollider/Extensions/Vowel/`          | Формантные таблицы Vowel (nix-пакет) |
| `~/.local/share/SuperCollider/Extensions/SC3plugins/`     | SC3-Plugins классы (nix-пакет)       |
| `/nix/store/*dirt-samples*/share/Dirt-Samples/`           | Банк сэмплов (~170MB, nix store)     |
| `~/src/music/tidal/samples/`                              | Свои сэмплы (имя папки = имя звука)  |
| `~/src/music/tidal/`                                      | Рабочая директория для .tidal файлов |
| `/run/current-system/sw/bin/tidal-ghci`                   | GHCi враппер                         |
| `/etc/nixos/modules/user/nix-maid/apps/supercollider.nix` | Модуль NixOS                         |
| `/etc/nixos/docs/howto/tidal-cycles.md`                   | Этот документ                        |

## Ссылки

- [TidalCycles](https://tidalcycles.org/) — официальный сайт
- [TidalCycles Docs](https://tidalcycles.org/docs/) — туториалы и reference
- [SuperDirt](https://codeberg.org/musikinformatik/SuperDirt) — аудиодвижок
- [tidal.nvim](https://github.com/grddavies/tidal.nvim) — Neovim плагин
