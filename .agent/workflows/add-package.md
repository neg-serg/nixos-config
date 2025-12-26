---
description: Add a new package to the configuration / Добавление нового пакета
---

# Add Package / Добавление пакета

## Steps / Шаги

1. **Find the right module** / Найти нужный модуль:
   - CLI tools → `modules/cli/`
   - GUI apps → `modules/user/nix-maid/apps/`
   - Dev tools → `modules/dev/`
   - Media → `modules/media/`

2. **Add package with comment** / Добавить пакет с комментарием:
   ```nix
   environment.systemPackages = [
     pkgs.my-package  # description of what it does
   ];
   ```

3. **Or for user packages** / Или для пользовательских пакетов:
   ```nix
   users.users.neg.packages = [
     pkgs.my-package  # description
   ];
   ```

4. **Rebuild** / Пересобрать:
   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Best Practices / Лучшие практики

- Always add inline comment / Всегда добавляйте комментарий
- Group related packages / Группируйте связанные пакеты
- Use explicit `pkgs.package` instead of `with pkgs;`

## Finding Packages / Поиск пакетов

```bash
nix search nixpkgs#package-name
```

Or visit: https://search.nixos.org/packages
