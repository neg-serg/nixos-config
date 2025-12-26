---
description: Create a new NixOS module / Создание нового модуля NixOS
---

# Add Module / Создание модуля

## Steps / Шаги

1. **Create module directory** / Создать директорию модуля:
   ```bash
   mkdir -p modules/my-domain/
   ```

2. **Create main module file** / Создать файл модуля:
   ```nix
   # modules/my-domain/default.nix
   { pkgs, lib, config, ... }: {
     imports = [ ./modules.nix ];
   }
   ```

3. **Create modules.nix** / Создать modules.nix:
   ```nix
   # modules/my-domain/modules.nix
   { pkgs, lib, config, ... }: {
     # Your configuration here
     environment.systemPackages = [
       pkgs.some-package  # description
     ];
   }
   ```

4. **Create README.md** / Создать README.md:
   ```markdown
   # My Domain Module / Модуль моего домена

   Description in English.
   Описание на русском.

   ## Includes / Включает
   - Feature 1 / Функция 1
   - Feature 2 / Функция 2
   ```

5. **Add to imports** / Добавить в импорты:
   Edit the appropriate role or profile to import your module.

## Module Structure / Структура модуля

```
modules/my-domain/
├── default.nix      # Entry point
├── modules.nix      # Main configuration
├── pkgs.nix         # Package lists (optional)
└── README.md        # Documentation
```

## Naming Conventions / Соглашения об именовании

- Lowercase directory names / Имена директорий в нижнем регистре
- Use hyphens for multi-word names / Дефисы для составных имён
- `modules.nix` for submodule imports / `modules.nix` для подмодулей
