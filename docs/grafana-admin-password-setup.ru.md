# Пароль администратора Grafana (SOPS)

Этот репозиторий настраивает Grafana так, чтобы админ‑пароль читался из SOPS‑зашифрованного файла и передавался через провайдер Grafana `$__file`. Если вас устраивает дефолтный `admin/admin` при первом запуске — можно ничего не делать, но перед публикацией UI стоит задать сильный пароль.

Поддерживаются два имени файла (берётся первый найденный):
- `secrets/grafana-admin-password.sops.yaml` (рекомендуется)
- `secrets/grafana-admin-password.sops` (бинарная альтернатива)

Расшифрованное содержимое должно быть одной строкой (без YAML‑ключей), т.к. Grafana получает путь к файлу со строкой пароля.

## Быстрая настройка (рекомендуется, YAML‑скаляр)

1) Создайте файл из одной строки (без кавычек):

```
echo 'YourStrongPasswordHere' > secrets/grafana-admin-password.sops.yaml
```

2) Зашифруйте SOPS с age‑получателями из `.sops.yaml` (подхватится автоматически):

```
sops -e -i secrets/grafana-admin-password.sops.yaml
```

3) Закоммитьте зашифрованный файл:

```
git add secrets/grafana-admin-password.sops.yaml
git commit -m "[secrets] grafana admin password (sops)"
```

4) Пересоберите/переключитесь. Grafana возьмёт пароль через `$__file{...}`.

## Альтернатива (бинарный файл)

Если предпочитаете бинарный SOPS‑файл `secrets/grafana-admin-password.sops`, зашифруйте его явно с age‑получателями из `.sops.yaml`:

```
# Получатели из .sops.yaml
AGE1="age1eggdzmjp2h4a68kn0j5zay72s7s6tc7qzak6cy9zp3dj0rwxxetsmz4t52"
AGE2="age1lnkpac97m7drx3k2ej5jwccfa99z4n2sxlezwzjfcevwqtvw9chs8knmtc"

printf '%s' 'YourStrongPasswordHere' > secrets/grafana-admin-password.sops
sops -e \
  --age "$AGE1" --age "$AGE2" \
  --input-type binary --output-type binary \
  -i secrets/grafana-admin-password.sops

git add secrets/grafana-admin-password.sops
git commit -m "[secrets] grafana admin password (sops binary)"
```

## Заметки
- Nix‑конфиг читает секрет только если файл существует; иначе Grafana падает на дефолт.
- Развёрнутый секрет устанавливается в root‑only путь и передаётся в `services.grafana.settings.security.admin_password = "$__file{...}"`.
- Ротируйте пароль, пере‑шифровывая файл и выполняя switch.
- Для HTTPS в LAN Grafana отдаётся через Caddy по `https://grafana.telfir` с внутренним CA Caddy. Скачайте CA по `/ca.crt` и добавьте в доверенные, если нужно.

