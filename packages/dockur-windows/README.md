# dockur-windows — авто-провижининг Windows VM (dockur/windows)

Кастомный образ на базе dockur/windows: при установке Windows автоматически
настраивается прокси (Edge policy + WinINET + env) и ставятся установщики из
`oem/installers/`.

## Механизм

dockur копирует смонтированный `/oem` на диск Windows в `C:\OEM` и во время
установки выполняет `C:\OEM\install.bat` (это встроенный хук OEM_SCRIPT).
`install.bat` запускает `setup.ps1`, который:

1. ставит системный прокси WinINET (`HKLM` → `192.168.2.88:10812`) — для GLM и GUI-приложений;
2. ставит политику Edge (`HKLM\Software\Policies\Microsoft\Edge` → `socks5://192.168.2.88:10811`);
3. прописывает env-переменные ALL_PROXY/HTTPS_PROXY/HTTP_PROXY (machine-wide);
4. тихо ставит всё из `oem/installers/` (Inno: /VERYSILENT, NSIS: /S, MSI: /qn);
5. пишет маркер `C:\OEM\provisioned.txt` и логи в `C:\OEM\install.log`.

## Использование

Вариант A — кастомный образ:

```bash
cd packages/dockur-windows
docker build -t dockur-windows-auto .
# и в docker run использовать docker.io/dockurr/windows → dockur-windows-auto
```

Вариант B — без пересборки образа (быстрая итерация):

```bash
docker run -d --name windows \
  -v <том с диском>:/storage \
  -v /etc/nixos/packages/dockur-windows/oem:/oem \
  ... (остальные флаги как в docs/howto/windows-vm-dockur.ru.md) \
  docker.io/dockurr/windows
```

## Установщики

Положи нужные .exe/.msi в `oem/installers/` перед стартом установки:
- `rtpMIDI` (tobias-erichsen.de) — сетевой MIDI-порт для GLM MIDI;
- `GLM` (MyGenelec) — сам софт Genelec (если поддерживает тихую установку;
  иначе ставится вручную после первой загрузки).

## Проверка

После загрузки Windows: на хосте должны появиться соединения VM к прокси
(`ss -tnp | grep 10812`), а в VM — `C:\OEM\provisioned.txt` и логи.

## Грабли: алиас .88 в контейнере

pasta (`--config-net`) копирует адреса хоста в контейнер — включая алиас
`192.168.2.88`, если он уже есть на net1. Тогда контейнер считает .88 своим
адресом и сам себе отвечает `Connection refused` на 10811/10812 (VM через
passt ходит тем же путём). После каждого пересоздания контейнера убирать:

```bash
docker exec windows ip addr del 192.168.2.88/24 dev net1
```

(Либо добавлять алиас .88 на хост ПОСЛЕ старта контейнера.)
