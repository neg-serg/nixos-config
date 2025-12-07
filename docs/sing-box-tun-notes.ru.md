## Sing-box TUN (VLESS Reality) status

- Секрет конфига: `/run/user/1000/secrets/vless-reality-singbox-tun.json` (от sops:
  `secrets/home/vless/reality-singbox-tun.json.sops`, раскатывается home-manager при наличии
  файла).
- Сервис: ручной запуск `systemctl start|stop|restart sing-box-tun`. Юнит прописывает policy
  routing:
  - `pref 100`: трафик до сервера 204.152.223.171 идёт по main.
  - `pref 200` + `table 200`: весь остальной трафик — `default dev sb0`.
  - DNS: `resolvectl dns sb0 1.1.1.1 1.0.0.1`, `resolvectl domain sb0 "~."`.
  - При старте сохраняет прежний default из table 200 в `/run/sing-box-tun/prev-default-route`,
    при остановке возвращает его (если был) и сбрасывает настройки DNS.
- Требования: установленный `sing-box` (в `environment.systemPackages`), секрет должен быть
  развёрнут (home-manager), нужен `CAP_NET_ADMIN` (root/systemd).
- Проверки: `ip rule`, `ip route show table 200` (должен быть `default dev sb0`),
  `curl --interface sb0 https://ifconfig.me`, `ping -I sb0 8.8.8.8`.
- Xray tun в nixpkgs без поддержки jsonv5/tun — удалён, используем только sing-box.
