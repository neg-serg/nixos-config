______________________________________________________________________

## description: Темизация Quickshell и Rofi

# Темизация

## Quickshell

### Конфигурация:

```
files/quickshell/
├── Bar/           # Статус-бар
├── Theme/         # Настройки темы
├── Settings/      # Пользовательские настройки
└── greeter/       # Экран входа
```

### Изменение цветов:

Редактировать `files/quickshell/Theme/panel.jsonc`:

```json
{
  "colors": {
    "primary": "#c1c1ff",
    "surface": "#131318"
  }
}
```

### Перезагрузка:

```bash
quickshell --quit && quickshell &
```

## Rofi

### Файлы тем:

```
packages/rofi-config/
├── colors.rasi    # Цвета
├── common.rasi    # Общие стили
├── askpass.rasi   # Запрос пароля
└── menu-*.rasi    # Стили меню
```

### Изменение темы:

Редактировать `packages/rofi-config/colors.rasi`:

```css
* {
    primary: #c1c1ff;
    surface: #131318;
    on-surface: #e4e1e9;
}
```

### Тест темы:

```bash
rofi -show drun -theme ~/.config/rofi/config.rasi
```

## Горячая перезагрузка

Для конфигов с impurity:

- Изменения применяются сразу
- Пересборка не нужна
