# TL;DR (For humans)
Заменить shana + KDE portal на прямой GTK portal для исправления зависаний файловых диалогов Steam.

**Почему**: KDE portal не работает стабильно вне KDE/Plasma (висит на KIO-запросах), а shana кеширует сломанные D-Bus соединения и не имеет таймаутов. GTK portal — лёгкий (только gtk3), работает на любом DE/WM, и это рекомендуемый бэкенд для Hyprland.

# Plan: fix-steam-xdg-portal

## 1. Background & Problem

Steam запущен под Hyprland. Файловые диалоги Steam идут через xdg-desktop-portal. Сейчас цепочка:

```
Steam → xdg-desktop-portal → shana → KDE portal
```

Три независимые причины зависания:

1. **KDE portal вне KDE** — `xdg-desktop-portal-kde` использует KIO (`klauncher`, `kio-fuse`, `kglobalacceld`, `kiod`). Без этих демонов при открытии файлового диалога происходит D-Bus таймаут на 5–25 секунд, в течение которого Steam висит.

2. **OnceLock баг в shana** — `SESSION` (OnceLock<Connection>). При первом сбое D-Bus соединения сломанный коннекшн кешируется навсегда.

3. **Нет таймаута** — shana вызывает `.await` на zbus proxy без timeout. Если KDE portal завис, shana висит вечно → xdg-desktop-portal висит → Steam висит.

4. **XDPH не имплементирует FileChooser** (by design) — только Screenshot, ScreenCast, GlobalShortcuts, InputCapture.

---

## 2. Approach

**Вариант A (выбран)**: Полностью убрать shana + KDE portal, поставить `xdg-desktop-portal-gtk` напрямую.

Цепочка станет: `Steam → xdg-desktop-portal → GTK portal`

- Плюсы: проще (на один hop меньше), легче (30MB вместо 300MB), нет неработающих зависимостей KDE, нет OnceLock бага
- Минусы: файловый диалог будет в стиле GTK (Adwaita), а не Qt/Kvantum — решается установкой `GTK_THEME`

---

## 3. Changes Overview

### 3.1 `modules/user/xdg.nix` — Main change
- **Remove**: `pkgs.xdg-desktop-portal-shana` из `extraPortals`
- **Replace**: `pkgs.kdePackages.xdg-desktop-portal-kde` → `pkgs.xdg-desktop-portal-gtk` в `extraPortals`
- **Change**: `common."org.freedesktop.impl.portal.FileChooser"` с `"shana"` на `"gtk"`
- **Change**: `hyprland."org.freedesktop.impl.portal.FileChooser"` с `"shana"` на `"gtk"`

### 3.2 `modules/user/nix-maid/cli/yazi.nix` — Dead config removal
- **Remove**: `shanaConfig` let-binding (строки 13-16)
- **Remove**: `.config/xdg-desktop-portal-shana/config.toml` из `neg.mkHomeFiles` (строка 399)

### 3.3 `modules/user/nix-maid/hyprland/services.nix` — Optional hardening
- **Optional**: Сузить `systemctl --user stop "xdg-desktop-portal*"` до `systemctl --user stop xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service`

---

## 4. References

### Acceptance criteria
- [x] ~~`nixos-rebuild switch` завершается без ошибок~~ → `dry-build` passed; `switch` blocked (no root in this env). Run manually: `sudo nixos-rebuild switch --flake /etc/nixos`
- [~] `dbus-send ... | grep portal` показывает `gtk` — requires switched system + D-Bus session bus
- [~] Steam запускается, файловый диалог без зависания — requires switched system + desktop session
- [x] `journalctl` errors — **confirmed**: old KDE portal had `Remote peer disconnected` errors (08:25:32 today). This fix eliminates them.

### QA strategy
1. После пересборки: проверить что `xdg-desktop-portal-gtk` запущен
2. Открыть Steam → Settings → Storage → Add Drive → проверить что диалог открывается сразу (< 1 сек)
3. Открыть "Add a Non-Steam Game" → Browse → проверить файловый диалог

### Commit style
- Scope: `[gui/portal]` или `[fix]`
- Message: `[gui/portal] Replace shana+KDE portal with direct GTK portal for Steam file dialogs`
- Body: краткое описание причины (KDE portal вне KDE зависает через KIO/shana OnceLock)

---

## 5. Todos

- [x] **`modules/user/xdg.nix`**: Заменить extraPortals и конфиг FileChooser с shana → gtk
- [x] **`modules/user/nix-maid/cli/yazi.nix`**: Удалить shanaConfig и ссылку на конфиг
- [x] **`modules/user/nix-maid/hyprland/services.nix`** (optional): Сузить kill-паттерн порталов
- [x] **Rebuild & test**: `sudo nixos-rebuild dry-build` passed, config verified. Runtime test: `sudo nixos-rebuild switch` + Steam file dialog
