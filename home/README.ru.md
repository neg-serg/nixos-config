# Конфигурация Home Manager

Этот репозиторий содержит конфигурацию Home Manager (flakes) для пользовательской среды. Включает
модульную настройку GUI (Hyprland), CLI‑инструментов, мультимедиа, почты, секретов и др.

- Гайд для агента (как работать в репо): см. `../docs/manual/manual.ru.md`
- Правила код‑стайла для Nix‑модулей: `STYLE.md`
- Флаги и опции: `modules/features.nix`

## Быстрые задачи (нужен `just`)

- Форматирование: `just fmt`
- Проверки: `just check`
- Только линт: `just lint`
- Переключить HM: `just hm-neg` или `just hm-lite`

> На системах с объединённым репозиторием (`/etc/nixos`) используйте
> `sudo nixos-rebuild switch --flake /etc/nixos#<host>`. Таргеты `just hm-*` оставлены для
> standalone/dev‑сценариев (WSL, удалённые хосты).

## Заметки

- Автоперезагрузка Hyprland отключена; перезагружайте вручную хоткеем.
- Quickshell Settings.json игнорируется и не должен добавляться в репозиторий.
- Конфиг Hyprland разбит по `modules/user/gui/hypr/conf`:
  - `bindings/*.conf`: apps, media, notify, resize, tiling, tiling-helpers, wallpaper, misc
  - `init.conf`, `rules.conf`, `workspaces.conf`, `autostart.conf`
  - Файлы линкованы в `~/.config/hypr` через Home Manager.
- Rofi: враппер `~/.local/bin/rofi` обеспечивает поиск темы (относительно конфига и в XDG data).
  - Темы находятся в `~/.config/rofi` и `~/.local/share/rofi/themes`; Mod4+c использует тему clip.
  - Линки тем генерируются из компактного списка (без ручных дублей в модуле).

### Индикатор раскладки (Quickshell + Hyprland)

- Индикатор раскладки в панели Quickshell обновляется мгновенно по событию `keyboard-layout` от
  Hyprland — без таймеров и дебаунсов.
- Для надёжности модуль определяет основное устройство ввода (клавиатуру с `main: true`) и
  предпочитает его события, игнорируя шум от псевдоустройств (`power-button`, `video-bus`,
  виртуальные клавиатуры).
- Если событие пришло не от основной клавиатуры, выполняется один быстрый снимок
  `hyprctl -j devices` для подтверждения — это сохраняет скорость в обычном пути и исправляет редкие
  расхождения.
- Клик по индикатору переключает текущую клавиатуру: `hyprctl switchxkblayout current next` (без
  запуска shell).
- Рекомендованный хоткей Hyprland для быстрого переключения:
  `bind = $M4, S, switchxkblayout, current, next` (обратите внимание на синтаксис с запятыми для
  диспетчера).
- Подробнее: quickshell/.config/quickshell/Docs/Config.md

### Floorp: панель навигации сверху

- Для Floorp панель навигации оставлена сверху. Перенос вниз через CSS‑хаки (в духе MrOtherGuy)
  отключён — он ломается при апдейтах темы Floorp/Lepton, вызывает нестабильность позиционирования
  попапов и панелей расширений.
- Оставлены только «безопасные» правки (findbar, компактные вкладки). Для отладки селекторов
  используйте `chrome://browser/content/browser.xhtml` и DevTools.
- Если очень нужно — можно включить вручную, поменяв `bottomNavbar = false` на `true` в
  `modules/user/web/floorp.nix`, но сопровождать CSS придётся самостоятельно.

### Floorp: приватность и Новая вкладка

- Усиленная приватность по умолчанию:
  - Строгая блокировка контента (ETP) и DNS‑over‑HTTPS через политики.
  - Отключены Telemetry, Studies и Pocket (через политики).
- «Новая вкладка» (Activity Stream) очищена: нет спонсорских плиток, Top Sites, Highlights, Top
  Stories и погоды.
- Подсказки в адресной строке: отключены Quicksuggest/Trending.
- Диалог выбора файлов использует XDG‑порталы (Wayland‑дружественно).

### Активация HM: пояснения

- Сообщение «Activating ensureTransmissionDirs»
  - Это шаг активации Home Manager, который создаёт служебные папки для Transmission в
    `~/.config/transmission-daemon/`.
  - Нужен, чтобы избежать ошибок первого запуска вида «resume: No such file or directory», особенно
    если каталог — симлинк или пустой.
  - Реализовано через `mkEnsureDirsAfterWrite` в `modules/user/torrent/default.nix` (создаёт
    `resume/`, `torrents/`, `blocklists/`).

## Быстрый старт

- Требования

  - Nix с включёнными flakes (`nix --version` должен работать; в конфиге Nix выставьте
    `experimental-features = nix-command flakes`).
  - Home Manager доступен (через flakes).
  - Опционально: `just` для удобных команд.

- Клонирование и переключение

  - **Единый репозиторий `/etc/nixos`.** Home Manager теперь живёт внутри системного репо. Отдельный
    клон для `~/.dotfiles` не нужен. Основная команда применения:
    - `sudo nixos-rebuild switch --flake /etc/nixos#<host>`
    - Проверка без переключения:
      `nix build .#nixosConfigurations.<host>.config.home-manager.users.<user>.activationPackage`
  - **Стэндэлон/не‑NixOS режим.** Если нужен отдельный HM (WSL, macOS и т.п.), допустим локальный
    клон:
    - `git clone --recursive git@github.com:neg-serg/nixos-home.git ~/.dotfiles`
    - Полный профиль: `home-manager switch --flake ~/.dotfiles/nix/.config/home-manager#neg`
    - Lite‑профиль: `home-manager switch --flake ~/.dotfiles/nix/.config/home-manager#neg-lite`

- Профили и фичи

  - Профиль задаётся опцией `features.profile` (`full` по умолчанию, `lite` для headless/minimal).
  - Включайте/выключайте стеки в `home.nix` через `features.*` (например, `features.gui.enable`,
    `features.mail.vdirsyncer.enable`).
  - Стек GPG включается `features.gpg.enable`.
  - Предпочтения Mozilla: `features.web.prefs.fastfox.enable` — быстрые твики (включено в full,
    выключено в lite).
  - Браузер по умолчанию: `features.web.default` = `floorp | firefox | librewolf | nyxt | yandex`.
    - Выбранный браузер доступен как `config.lib.neg.web.defaultBrowser`.
    - Полная таблица — `config.lib.neg.web.browsers`.
  - Аудио: `features.media.audio.core/apps/creation/mpd.enable` — ставит TUI‑клиент `rmpc`,
    Qt‑клиент `pkgs.neg.cantata`, экспортирует `MPD_HOST`/`MPD_PORT` и при желании автозапускает
    Cantata (`media.audio.mpd.cantata.autostart = true;`).
  - Трейдинг: `features.finance.tws.enable` ставит Trader Workstation от Interactive Brokers (по
    умолчанию выключено).

- Секреты (sops-nix)

  - Секреты лежат в `secrets/` и подключаются через sops-nix из `home.nix` и модулей.
  - Убедитесь, что ключ `age` доступен, затем расшифровка произойдёт при активации. См. `secrets/` и
    `.sops.yaml`.

## Команды

- Форматирование: `just fmt`
- Проверки: `just check`
- Только линт: `just lint`
- Переключить HM: `just hm-neg` или `just hm-lite`

## Полезно знать

- Перезагрузка Hyprland — только вручную (см. hotkey в `modules/user/gui/hypr/conf/bindings.conf`).
- Юниты systemd (user) используют пресеты через `lib.neg.systemdUser.mkUnitFromPresets`.
- См. `../docs/manual/manual.ru.md` для API‑хелперов и соглашений; `STYLE.md` — для стиля и коммит‑месседжей.

## Просмотрщики и лаунчеры

- Просмотр изображений

  - Враппер `swayimg-first` ставится как `~/.local/bin/swayimg`.
    - В Hypr заданы правила для `swayimg` (float/size/position) и роутинг воркспейсов.

- Лаунчер Rofi

  - `~/.local/bin/rofi` гарантирует, что `-theme <name|name.rasi>` находит тему (относительно
    конфига или в XDG data).
  - `menu.rasi`, `menu-columns.rasi`, `viewer.rasi` и требуемые `win/*.rasi` линкуются в
    `$XDG_DATA_HOME/rofi/themes` для использования через `-theme`.
  - Для emoji‑пикера можно добавить свой `~/.local/bin/rofi-emoji`.
  - Автопринятие включено по умолчанию (`-auto-select`). При необходимости отключайте флагом
    `-no-auto-select` для конкретного вызова.

- Браузеры Mozilla

  - Firefox, LibreWolf и Floorp настраиваются через единый конструктор `mkBrowser` в
    `modules/user/web/mozilla-common-lib.nix`.
  - Каждый модуль вызывает `common.mkBrowser { name, package, profileId ? "default"; }` и может
    расширять конфиг.
  - Используйте `settingsExtra`, `addonsExtra`, `policiesExtra`, `nativeMessagingExtra`,
    `profileExtra` для переопределений.

## Заметки для разработчиков

- Сабжекты коммитов должны начинаться со скоупа `[scope]` (принуждается хуком
  `.githooks/commit-msg`).
  - Включить хуки: `just hooks-enable` или `git config core.hooksPath .githooks`
