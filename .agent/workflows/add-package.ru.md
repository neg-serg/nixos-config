______________________________________________________________________

## description: Добавление нового пакета

# Добавление пакета

## Шаги

1. **Найти нужный модуль**:

   - CLI tools → `modules/cli/`
   - GUI apps → `modules/user/nix-maid/apps/`
   - Dev tools → `modules/dev/`
   - Media → `modules/media/`

1. **Добавить пакет с комментарием**:

   ```nix
   environment.systemPackages = [
     pkgs.my-package  # описание пакета
   ];
   ```

1. **Или для пользовательских пакетов**:

   ```nix
   users.users.neg.packages = [
     pkgs.my-package  # описание
   ];
   ```

1. **Пересобрать**:

   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Лучшие практики

- Всегда добавляйте комментарий
- Группируйте связанные пакеты
- Используйте явный `pkgs.package` вместо `with pkgs;`

## Поиск пакетов

```bash
nix search nixpkgs#package-name
```

Или посетите: https://search.nixos.org/packages
