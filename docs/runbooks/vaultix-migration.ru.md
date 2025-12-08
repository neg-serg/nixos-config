# Переход на Vaultix для управления секретами Home Manager

Этот документ описывает алгоритм перевода текущей конфигурации Home Manager (где задействован только
`sops-nix`) на `vaultix`, как это сделано в `/home/neg/src/dotfiles`. Предполагается, что HM-модули
в конечном итоге подключаются из конфигурации NixOS, поскольку `vaultix` предоставляет модуль именно
для NixOS и собственные CLI-инструменты.

## Зачем нужен Vaultix

| Аспект | Только `sops-nix` | `vaultix` + `sops-nix` | | --- | --- | --- | | Формат шифрования |
Любой бэкенд (Age/GPG) | Только Age, в духе рекомендаций NixOS | | Распределение получателей |
Ручное для каждого секрета | Центральный блок `vaultix.configure` раздаёт файлы по узлам и
дополнительным получателям | | Начальная инициализация | Ручное копирование / расшифровка | CLI
`vault edit` / `vault renc` пересобирает секрет под конкретный хост и кладёт его в нужный путь при
сборке | | Доступность модулей | Удобно для HM | Основная интеграция в NixOS (лучше использовать
вместе с HM flakes) |

### Плюсы

- **Единый источник правды**: `vaultix.configure` знает обо всех узлах и автоматически формирует
  набор секретов для каждого.
- **Только публичные Age-ключи**: не нужно раздавать приватные ключи или заводить отдельные KMS.
- **Удобный bootstrap**: `vault edit secret.age` открывает секрет в редакторе и возвращает
  зашифрованную версию после сохранения.
- **Хорошая связка с NixOS**: модуль гарантирует наличие секретов до запуска соответствующих
  сервисов.

### Минусы

- На чистом `home-manager switch --flake` вне NixOS модуль недоступен (нужно использовать HM внутри
  NixOS).
- Требуется ещё один внешний инструмент и дополнительная зависимость.
- Пользовательские секреты всё равно удобнее держать в `sops-nix`, пока вы полностью не перейдёте на
  Age.

## Алгоритм миграции

1. **Проинвентаризируйте существующие секреты**

   - Составьте список из `secrets/default.nix`, зафиксируйте пути, владельцев, права.
   - Решите, какие секреты обязательны на этапе активации системы (пароли root, ключи VPN/WireGuard
     и т.п.).

1. **Добавьте вход `vaultix` во flake**

   ```nix
   inputs.vaultix.url = "github:milieuim/vaultix";
   ```

   Выполните `nix flake update`, чтобы зафиксировать зависимость.

1. **Экспортируйте `vaultix` в outputs**

   - Если уже объявлены `nixosConfigurations`, просто добавьте модуль:
     ```nix
     outputs = { self, nixpkgs, vaultix, ... }:
     {
       nixosConfigurations.host = nixpkgs.lib.nixosSystem {
         modules = [
           ./hosts/host
           vaultix.nixosModules.default
           # остальные модули …
         ];
         specialArgs = { inherit self inputs; };
       };
     }
     ```
   - Для автономного HM прокиньте `vaultix` через `extraSpecialArgs`, чтобы модули могли ссылаться
     на те же опции (это пригодится, когда вы переиспользуете их в NixOS).

1. **Опишите `vaultix.configure` рядом с outputs**

   ```nix
   vaultix = vaultix.configure {
     nodes = self.nixosConfigurations;
     identity = self + "/secrets/identities/master.pub";
     extraRecipients = [
       # Дополнительные Age-получатели (CI, аварийный ключ и т.д.)
     ];
     defaultSecretDirectory = "./secrets";
     cache = "./secrets/.cache";
     extraPackages = [ self.packages.x86_64-linux.age-plugin-openpgp-card ];
   };
   ```

   Так вы сообщаете `vaultix`, где лежит ключ подписи и какой набор хостов нужно обслуживать.

1. **Опишите метаданные секретов** Создайте `secrets/default.nix` вида:

   ```nix
   {
     config,
     ...
   }:
   let
     username = config.dots.user.username;
   in
   {
     vaultix.secrets = {
       rootPass = {
         file = ./common/root.age;
         owner = "root";
         group = "users";
       };
       userPass = {
         file = ./common/user.age;
         owner = username;
         group = "users";
       };
       # … другие файлы
     };
     vaultix.beforeUserborn = [ "rootPass" "userPass" ];
   }
   ```

   Каждая запись связывает Age-файл с владельцем/группой, которые NixOS выставит при активации.

1. **Перешифруйте содержимое в Age**

   - Для любого старого sops-файла выполните `sops -d file | vaultix renc new-secret.age` либо
     используйте `rage`/`age` через `vault edit`.
   - Сохраните `.age` в дереве `secrets/`, на которое ссылается конфигурация.

1. **Перепроверьте потребители** Замените обращения вроде `config.sops.secrets."github-netrc".path`
   на `config.vaultix.secrets.<name>.path` в сервисах и unit-файлах.

1. **Протестируйте цепочку**

   - `nix run .#vault edit secrets/common/root.age` — проверка редактирования.
   - `sudo nixos-rebuild switch --flake .#host` — проверка внедрения.
   - `ls -l /run/secrets` (или ваш путь) — контроль владельцев и прав.

1. **Постепенно отключайте `sops-nix`** Можно держать оба механизма параллельно, пока не перенесёте
   все данные.

## Практические советы

- Храните публичные Age-ключи всех контрибуторов в `secrets/identities/`, приватные — только
  локально.
- Держите `secrets/.cache` в `.gitignore`, чтобы не коммитить временные файлы `vaultix`.
- Экспортируйте CLI `self.vaultix.app.${system}.edit` в devShell — это упростит редактирование
  секретов.
- Явно фиксируйте, какие секреты должны существовать до `userborn`, через `vaultix.beforeUserborn`.

## Итог

Переход на `vaultix` требует добавить новый вход во flake, описать `vaultix.configure` и по очереди
перешифровать существующие секреты в формат Age. После этого секреты проще распределять между
хостами, а процессы первичной настройки становятся предсказуемыми.
