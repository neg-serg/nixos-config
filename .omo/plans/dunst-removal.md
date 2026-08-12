# dunst-removal — Work Plan (полная санация, НЕ выполнена)

> Статус: план подготовлен 2026-08-06. Демон уже ОТКЛЮЧЁН (см. коммит
> `[gui/notifications] Disable dunst daemon` — убран `systemd.user.services.dunst`,
> пакеты/конфиг/биндинги остались). Этот план — полное удаление dunst.

## TL;DR (For humans)

**Что вы получите:** dunst исчезнет из системы полностью (пакеты, dunstrc, биндинги, fallback'и).
Уведомления перейдут на quickshell (vicinae) — при условии, что он реализует
`org.freedesktop.Notifications` (проверить, шаг 3).

**Почему такой подход:** демон уже не нужен; quickshell-виджеты частично дублируют его (см.
`pic-notify`: основной путь — quickshell, dunst — fallback). Санация убирает мёртвый код и путаницу
из двух уведомителей.

**Что НЕ будет сделано:** `.zcompdump` (генерируемый), `.omo/drafts|plans` (исторические планы),
отключение quickshell.

**Объём (оценка):** ~6 файлов, 1 волна, 1 коммит.

## Текущее состояние (карта dunst, установлено 2026-08-06)

| Файл | Что | Действие | |---|---|---| | `modules/user/nix-maid/gui/dunst.nix` | модуль: systemd
user service (УЖЕ удалён), `pkgs.dunst`+`kora-icon-theme`, dunstrc, mkHomeFiles | удалить модуль
целиком | | `modules/user/nix-maid/default.nix:16` | импорт `./gui/dunst.nix` | удалить импорт | |
`modules/user/nix-maid/gui/default.nix:4` | импорт `./dunst.nix` | удалить импорт (проверить: оба
default.nix подключены? если да — был двойной импорт) | |
`modules/user/nix-maid/session/utils.nix:20` | `pkgs.dunst` (дубль пакета) | удалить | |
`files/gui/hy/hyprland.lua:231-232` | M4+n `dunstctl history-pop`, M4+space `dunstctl close-all` |
заменить на quickshell-эквиваленты или удалить; проверить конфликт M4+space с overlay-dismissal
(M4+Escape / M4+Shift+K / M4+Shift+D рядом) | |
`modules/user/nix-maid/gui/wlr-which-key.nix:207-212` | key `n` → history-pop, SUPER+space →
close-all | удалить записи или заменить | | `packages/local-bin/bin/qr` (строки ~30-50) |
`command -v dunstify` fallback (условный) | оставить (безвреден) или убрать fallback | |
`packages/local-bin/bin/pic-notify` (~85-90) | fallback notify-send если нет quickshell | оставить;
обновить комментарий про dunst | | `.zcompdump` | completion-кэш zsh | НЕ трогать |

## Scope

**IN:**

- Удалить `modules/user/nix-maid/gui/dunst.nix` + оба импорта
- Убрать `pkgs.dunst` из `session/utils.nix`
- Почистить биндинги `dunstctl` в `hyprland.lua` и `wlr-which-key.nix`
- (По результату шага 3) подтвердить quickshell как замену уведомлений

**OUT:**

- `kora-icon-theme` (проверить grep `kora` — вероятно, используется не только dunst)
- `.zcompdump`, исторические .omo-планы
- Рантайм-маска `~/.config/systemd/user/` (каталог read-only, управляется nix-maid — маска
  невозможна; после switch юнит исчезнет сам)

## Шаги

1. **Проверка замены:** quickshell/vicinae реализует `org.freedesktop.Notifications`?
   - grep `Notifications`/`mpris`/`notify` в `modules/user/nix-maid/gui/quickshell.nix`,
     `caelestia-shell.nix`, файлах vicinae (files/gui/quickshell\*)
   - Проверка: `busctl --user list | grep -i notification` на живой системе
   - **Если НЕ реализует** — решение с юзером: перенести уведомления на quickshell (план
     дополняется) или оставить dunst (санация отменяется)
1. Удалить модуль + импорты (default.nix:16, gui/default.nix:4), убрать пакет из utils.nix
1. Биндинги: hyprland.lua (M4+n, M4+space), wlr-which-key.nix (key n, SUPER+space) —
   заменить/удалить
1. Проверить grep `dunst|dunstctl|dunstify|notify-send` по репо — не осталось ли ссылок (кроме
   `command -v` fallback'ов)
1. dry-build + `sudo nixos-rebuild switch --flake /etc/nixos#odin`
1. Верификация: `which dunst dunstctl dunstify` пусто; `pgrep dunst` пусто;
   `systemctl --user status dunst` → not-found; `notify-send test` через quickshell — уведомление
   приходит
1. Коммит: `[gui/notifications] Remove dunst notification daemon`

## Риски

- quickshell не предоставляет Notifications → потеря уведомлений (шаг 1 решает до удаления)
- M4+space занят overlay-dismissal quickshell → конфликт биндингов (проверить при чистке)
- Двойной импорт dunst.nix (default.nix + gui/default.nix) — после удаления проверить, что ничего не
  сломано (dry-build)

## QA

- `nix eval --json '.#nixosConfigurations.odin.config.systemd.user.services'` → нет dunst
- `nixos-rebuild dry-build` exit 0
- `which dunst*` пусто, `notify-send` работает через quickshell
- Биндинги в wlr-which-key/hyprland.lua не ссылаются на dunstctl

## Commit

`[gui/notifications] Remove dunst notification daemon` — один коммит, все файлы сразу.
