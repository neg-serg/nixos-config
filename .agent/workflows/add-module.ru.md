---
description: Создание нового модуля NixOS
---

# Создание модуля

## Шаги

1. **Создать директорию модуля**:

   ```bash
   mkdir -p modules/my-domain/
   ```

1. **Создать файл модуля**:

   ```nix
   # modules/my-domain/default.nix
   { pkgs, lib, config, ... }: {
     imports = [ ./modules.nix ];
   }
   ```

1. **Создать modules.nix**:

   ```nix
   # modules/my-domain/modules.nix
   { pkgs, lib, config, ... }: {
     # Your configuration here
     environment.systemPackages = [
       pkgs.some-package  # description
     ];
   }
   ```

1. **Создать README.md**:

   ```markdown
   # Модуль моего домена

   Описание на русском.

   ## Включает
   - Функция 1
   - Функция 2
   ```

1. **Добавить в импорты**: Отредактируйте соответствующую роль или профиль для импорта вашего модуля.

## Структура модуля

```
modules/my-domain/
├── default.nix      # Точка входа
├── modules.nix      # Основная конфигурация
├── pkgs.nix         # Списки пакетов (опционально)
└── README.md        # Документация
```

## Соглашения об именовании

- Имена директорий в нижнем регистре
- Дефисы для составных имён
- `modules.nix` для подмодулей
