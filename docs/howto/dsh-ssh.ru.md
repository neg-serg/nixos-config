# dsh-ssh: SSH-операции, веб-терминал и localhost для агента

Плагин `@linxin666/dsh-ssh` даёт в dsh web панель **Remote SSH** (сайдбар), веб-терминал (xterm.js),
агентские тулзы `ssh_list/ssh_exec/ssh_upload/ssh_download/ssh_tunnel/ssh_cluster` и слэш-команды
`/ssh*`. Краткая версия для агента — скилл `~/.dsh/skills/dsh-ssh/SKILL.md`; здесь — хост-сторона,
решения и ограничения.

## Как включён

1. **Профиль** (`modules/user/nix-maid/apps/dsh-market.nix`):
   - зависимость `@linxin666/dsh-ssh: workspace:^0.1.16` + symlink `node_modules/@linxin666/dsh-ssh`
     → форк `~/src/1st-level/@projects/dsh-web-ui/packages/dsh-ssh`;
   - из `cordis.patch.yml` снимается `- id: ssh / disabled: true`. Строка `ssh` приходит из
     бандл-патча `dsh-web-ui-all`, отдельная insert-строка не нужна (иначе дубликат id).
1. **Скин** (`packages/dsh-terminal-ui` в форке): снят `display:none` с `.mL8Uca_entry` — это кнопка
   входа в панель Remote SSH.
1. Пакет форка уже собран (`lib/` коммитится в форке).

Откат: вернуть `- id: ssh / disabled: true` в патч и убрать dep/symlink в модуле.

## localhost (odin)

- Хост `localhost` использует выделенный ключ агента **`~/.ssh/agent/dsh-agent-key`**; в
  `authorized_keys` запись ограничена `from="127.0.0.1,::1"` (личный `id_ed25519` остаётся как
  запасной — он тоже авторизован).
- sshd (`hosts/odin/services.nix` + `modules/servers/openssh`): `openssh.allowTcpForwarding = true`
  \+ `PermitOpen 127.0.0.1:* [::1]:*` — туннели разрешены, но **только на loopback** (pivot в LAN
  невозможен). ⚠️ IPv6 в PermitOpen обязательно в скобках: `[::1]:*` (без скобок sshd падает с
  "PermitOpen bad port number").
- Шире (если понадобятся туннели до LAN): заменить PermitOpen на нужные host-маски
  (`PermitOpen 10.0.2.*:*` и т.п.) — осознанно, это ослабляет hardening.

## Хосты

- Хранилище: `~/.dsh/dsh-ssh.json` (0600, владелец neg). Запись: alias, host, port, user, auth
  {kind: key|password, keyPath}, proxyJump[], tags[], environment.
- REST loopback-only (`http://127.0.0.1:3080/api/dsh-ssh`): `GET/POST /hosts`,
  `PATCH/DELETE /hosts?alias=<x>`, `POST /hosts/import-ssh-config` (импорт из `~/.ssh/config`,
  существующие алиасы пропускаются), `POST /test`.
- Key-аутентификация требует `auth.keyPath`.
- Веб-терминал: WS `/api/dsh-ssh/terminal?alias=<x>&cols=120&rows=40`.

## Команды терминала (packages/local-bin/bin)

`ssh-hosts` — список хостов; `ssh-exec [alias] <cmd...>` — выполнить команду; `ssh-test [alias]` —
проверка соединения; `ssh-tunnels` — активные туннели. После добавления в репо нужен
`nh os switch /etc/nixos#odin --option substitute false`.

## Ограничения и решения

- Туннели на odin — loopback-only (см. выше): безопасно по умолчанию.
- `ssh_download` не умеет каталоги — только файлы; `ssh_upload` каталоги умеет.
- `ssh_exec` с авто-реконнектом (до 3 раз) может повторить неидемпотентную команду.
- Пароли в `dsh-ssh.json` — plaintext (0600), в репо не попадают.
- Вывод команд может содержать чувствительные данные.

## Проверка

```bash
ssh-hosts; ssh-test localhost; ssh-exec localhost 'hostname'
ssh-tunnels                       # нет активных
# туннель end-to-end:
ssh_tunnel(start, localhost:22) → ssh -p <localPort> neg@127.0.0.1
```
