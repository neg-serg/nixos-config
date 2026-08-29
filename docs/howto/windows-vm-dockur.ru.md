# Dockur Windows VM на odin: USB-проброс GLM и прокси

Windows 11 крутится в контейнере **dockur/windows** (QEMU/KVM), диск — в podman-томе (переживает
пересоздание контейнера). Доступ: RDP `127.0.0.1:3389` (пользователь из `USERNAME`, пароль из
`PASSWORD`) или веб-интерфейс noVNC/KasmVNC `http://127.0.0.1:8006`.

## Запуск контейнера

Диск лежит в podman-томе `f1047db9589f…` (bind в `/storage`). Команда пересоздания:

```bash
docker run -d --name windows \
  -v f1047db9589f2c0f4f8f31b6b4b4eeca2e4954d482ed0b8ed605cd3eb9033dc8:/storage \
  -v /dev/bus/usb:/dev/bus/usb \
  --device=/dev/kvm \
  --device /dev/bus/usb \
  --cap-add NET_ADMIN \
  -p 8006:8006 -p 3389:3389/tcp -p 3389:3389/udp \
  -e VERSION="win11" -e USERNAME="neg" -e PASSWORD="пароль" \
  -e RAM_SIZE="16G" -e DISK_SIZE="120G" -e CPU_CORES="2" \
  -e TPM_VERSION="2.0" -e SECURE_BOOT="Y" \
  -e ARGUMENTS="-device usb-host,vendorid=0x1781,productid=0x0e39" \
  --stop-timeout 120 \
  docker.io/dockurr/windows
```

Ключевые флаги:
- `-v f1047db9…:/storage` — постоянный диск (Windows установлена один раз, пересоздания не теряют её).
- `-v /dev/bus/usb:/dev/bus/usb` — **живой** bind-mount USB. `--device /dev/bus/usb` НЕ
  достаточно: podman копирует ноды при старте (снимок) и не видит устройства, воткнутые после.
- `-e ARGUMENTS="-device usb-host,…"` — проброс USB-устройства в QEMU (hotplug-аналог —
  `device_add usb-host,vendorid=…,productid=…` через монитор).

## USB-проброс Genelec GLM (Gnet Adapter)

Устройство: `1781:0e39` (Bus 009). Три грабли, без которых «проброс не виден»:

1. **User-namespace контейнера**: root внутри = `nobody` на хосте. USB-ноды создаются udev с
   правами `0664 root:root` → контейнер получает `EPERM` и не может открыть устройство
   (QEMU показывает фейковое `USB Host Device` на 1.5 Mb/s вместо `Gnet Adapter` на 12 Mb/s).
   Лечится udev-правилом (в `hosts/odin/hardware.nix`):
   ```
   SUBSYSTEM=="usb", ATTR{idVendor}=="1781", ATTR{idProduct}=="0e39", MODE="0666"
   ```
   Runtime-проверка: `chmod 666 /dev/bus/usb/009/004` (после перевтыкания нода может смениться).
2. **Снимок USB**: `--device /dev/bus/usb` копирует ноды при старте. Живой вариант — bind-mount
   `-v /dev/bus/usb:/dev/bus/usb` (см. команду выше).
3. **udev может не создать ноду** для необычных HID-устройств: sysfs есть, `/dev/bus/usb` — нет.
   Триггер: `sudo udevadm trigger --attr-match=idVendor=1781`.

Проверка проброса (детерминированно, без GUI):

```bash
printf 'info usb\n' | timeout 5 docker exec -i windows nc -U /run/shm/monitor.sock
# Ожидаем: Device 0.2, Port 2, Speed 12 Mb/s, Product Gnet Adapter
# Плохо:    Device 0.0, Port 2, Speed 1.5 Mb/s, Product USB Host Device
```

## Сеть VM: конфликт IP и алиас хоста

pasta/passt отдают VM **тот же IP, что у хоста** (`192.168.2.87`) — VM физически не может
достучаться до хоста по его основному адресу. Поэтому на net1 добавлен **алиас `192.168.2.88`**
(декларативно в `hosts/odin/networking.nix` — Address списком):

```nix
Address = [
  "192.168.2.87/24"
  "192.168.2.88/24"
];
```

Все VM-прокси ходят через `192.168.2.88`. (Рантайм-алиас `ip addr add …` смывается networkd —
поэтому он в конфиге.)

## Прокси для VM (внутри хостового sing-box)

Два беспарольных inbound'а, добавлены в генератор `packages/local-bin/bin/proxy`
(теги `in-lan-vm` / `in-lan-vm-http`):

| Порт | Тип | Для чего |
|---|---|---|
| `10811` | SOCKS5 | Chromium/Edge (не умеют SOCKS-авторизацию) |
| `10812` | HTTP CONNECT | системный прокси WinINET — GLM и др. GUI-приложения (WinINET не умеет SOCKS) |

Фаервол (`modules/system/net/firewall.nix`): оба порта разрешены только из приватных диапазонов
(`10/8`, `172.16/12`, `192.168/16`), как и `10810`.

## Настройка Windows внутри VM

- **Edge** (только браузер) — политика перекрывает всё остальное:
  ```
  reg add "HKCU\Software\Policies\Microsoft\Edge" /v ProxyMode /t REG_SZ /d fixed_servers /f
  reg add "HKCU\Software\Policies\Microsoft\Edge" /v ProxyServer /t REG_SZ /d "socks5://192.168.2.88:10811" /f
  ```
- **Системный прокси WinINET** (GLM, остальные GUI-приложения; Edge не затронут):
  ```
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "192.168.2.88:10812" /f
  ```
- **Консольные утилиты** (новые окна):
  `setx ALL_PROXY/HTTPS_PROXY/HTTP_PROXY "socks5h://192.168.2.88:10811"`.

## Проверки и отладка

- IP выхода через прокси ≠ прямой:
  ```bash
  curl -s http://api.ipify.org                      # прямой:  178.237.248.44
  curl -s -x http://192.168.2.88:10812 http://api.ipify.org   # нода: 193.29.139.195
  ```
- VM реально ходит через прокси (живые соединения VM через passt):
  ```bash
  ss -tnp | grep 10812   # ESTAB 192.168.2.87:… -> 192.168.2.88:10812 (passt.avx2)
  ```
- Лог прокси: `journalctl --user -u sing-box-proxy`. DNS-таймауты
  (`lookup failed … context deadline exceeded`, DoH 1.1.1.1) — транзиентные, не требуют действий.
- **GLM «Cloud connection error» / 400**: облако Genelec (`glmcloud.genelec.com`) доступно и
  напрямую, и через прокси (curl → 200). 400 — это API/аккаунт Genelec, не сеть и не прокси.

## MIDI-управление GLM из Linux (rtpmidid → rtpMIDI → GLM 5)

GLM 5 умеет MIDI-remote (volume/mute/dim/power). Цепочка: Linux MIDI (Tidal/SuperCollider/CLI) →
ALSA seq → **rtpmidid** (пакет `neg.rtpmidid`, демон RTP-MIDI/AppleMIDI, user-сервис `rtpmidid`) →
UDP 5004/5005 → **rtpMIDI** (Tobias Erichsen, бесплатный виртуальный MIDI-порт в Windows) → GLM 5.

### Linux (odin)

- Пакет `packages/rtpmidid` (собрано, installPhase копирует `src/rtpmidid` — install-таргета в
  проекте нет), зарегистрирован в `packages/overlays/tools.nix` как `neg.rtpmidid`.
- User-сервис `rtpmidid` (`modules/user/nix-maid/sys/user-services.nix`): демон с `--name GLM`,
  автозапуск. Проверка портов: `aconnect -l` / `aplaymidi -l`.
- Обёртка `glm-midi` (`packages/local-bin/bin/glm-midi`): шлёт CC в порт rtpmidid.

### CC-карта GLM 5 MIDI (из VOL20toGenelecGLM/CONSTANTS.md)

| CC | Функция |
|---|---|
| 20 | абсолютная громкость 0..127 (dB = value − 127) |
| 21 / 22 | громкость + / − |
| 23 | Mute (toggle) |
| 24 | Dim (toggle) |
| 28 | Power (toggle) |

В GLM: Settings → MIDI → «Enable GLM MIDI interface»; Mute/Dim/Power — в режиме Toggle.

### Контейнер: проброс UDP для RTP-MIDI

`docker run` нуждается в `-p 5004:5004/udp -p 5005:5005/udp` (или `-e USER_PORTS="5004/udp,5005/udp"`)
— Linux → VM трафик RTP-MIDI идёт через опубликованные порты (у VM и хоста конфликт IP, прямое
соединение невозможно).

### Использование

```bash
glm-midi volume 60        # громкость 0..127
glm-midi volume -18dB     # или в дБ
glm-midi mute             # toggle
glm-midi dim              # toggle
glm-midi power            # toggle
glm-midi vol+ 3           # +3 шага
```

Tidal/SuperCollider: отправлять CC на ALSA-порт rtpmidid (например, SC: `MIDIClient.init; MIDIOut(port)`).

## Затронутые файлы

- `hosts/odin/default.nix` — флаг `features.net.proxy.enable`
- `hosts/odin/networking.nix` — алиас `192.168.2.88/24`
- `hosts/odin/hardware.nix` — udev-правило Genelec GLM (0666)
- `modules/system/net/firewall.nix` — порты 10811/10812
- `packages/local-bin/bin/proxy` — inbound'ы `in-lan-vm` (SOCKS 10811) и `in-lan-vm-http` (HTTP 10812)
