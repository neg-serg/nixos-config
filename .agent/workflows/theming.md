---
description: Quickshell and Rofi theming / Темизация Quickshell и Rofi
---

# Theming / Темизация

## Quickshell

### Configuration / Конфигурация:
```
files/quickshell/
├── Bar/           # Status bar / Статус-бар
├── Theme/         # Theme settings / Настройки темы
├── Settings/      # User settings / Пользовательские настройки
└── greeter/       # Login greeter / Экран входа
```

### Modify Colors / Изменение цветов:
Edit `files/quickshell/Theme/panel.jsonc`:
```json
{
  "colors": {
    "primary": "#c1c1ff",
    "surface": "#131318"
  }
}
```

### Reload / Перезагрузка:
```bash
quickshell --quit && quickshell &
```

## Rofi

### Theme Files / Файлы тем:
```
packages/rofi-config/
├── colors.rasi    # Color definitions / Цвета
├── common.rasi    # Shared styles / Общие стили
├── askpass.rasi   # Password prompt / Запрос пароля
└── menu-*.rasi    # Menu styles / Стили меню
```

### Modify Theme / Изменение темы:
Edit `packages/rofi-config/colors.rasi`:
```css
* {
    primary: #c1c1ff;
    surface: #131318;
    on-surface: #e4e1e9;
}
```

### Test Theme / Тест темы:
```bash
rofi -show drun -theme ~/.config/rofi/config.rasi
```

## Hot Reload / Горячая перезагрузка

For impurity-enabled configs / Для конфигов с impurity:
- Changes apply immediately / Изменения применяются сразу
- No rebuild needed / Пересборка не нужна
