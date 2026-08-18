# TPM-sudo — беспарольный sudo через TPM (без ручных действий)

Как получить `sudo` без ввода пароля, но с защитой: приватный SSH-ключ живёт **внутри TPM**
(неэкспортируемый) и подписывает запросы без PIN; `sudo` аутентифицируется по ssh-agent через
`pam_ssh_agent_auth`.

## Как это работает

```
sudo → pam_ssh_agent_auth → ssh-agent → PKCS#11 (tpm2-pkcs11) → TPM подписывает → ok
```

- Ключ **не покидает TPM** — его нельзя вытащить с машины.
- Пустой PIN → **ноль ручных действий** после разовой настройки.
- `sudo` не спрашивает пароль: `pam_ssh_agent_auth` вставлен как `auth sufficient` и `nixpkgs` сам
  добавляет `Defaults env_keep+=SSH_AUTH_SOCK`.

## Флаг

`features.security.tpmSudo.enable` (по умолчанию `false`). Включение — в `hosts/odin/default.nix`.
Модуль `modules/security/tpm-sudo.nix` при включении:

- включает `security.tpm2` + `security.tpm2.pkcs11` + `tctiEnvironment`;
- включает `security.pam.sshAgentAuth` + `sudo.sshAgentAuth`;
- разблокирует TPM-модули ядра (`kernel/params.nix`, `hosts/odin/hardware.nix`);
- добавляет `tpm2-pkcs11` в `agentPKCS11Whitelist` (`system/net/ssh.nix`);
- создаёт юнит `tpm2-ssh-add.service` — автозагрузка ключа в агент при логине.

## Шаг 1 — включить fTPM в UEFI/BIOS

У `odin` (Ryzen) — «AMD fTPM» / «PSP fTPM». В BIOS: **Advanced → AMD fTPM configuration → TPM Device
Selection → Firmware TPM** → Enabled.

> Без этого шага включать флаг нельзя: система будет ждать устройство `tpmrm` при загрузке (та самая
> пауза, из-за которой TPM был отключён).

## Шаг 2 — включить флаг

```nix
# hosts/odin/default.nix
features.security.tpmSudo.enable = true;
```

## Шаг 3 — пересобрать

```bash
just fmt && just check
nh os switch /etc/nixos#odin --option substitute false
```

## Шаг 4 — проверить TPM

```bash
ls -l /dev/tpmrm0            # root:tss 0660
tpm2_getrandom 8 | xxd       # TPM отвечает байтами
groups | grep -w tss         # пользователь в группе tss
```

## Шаг 5 — создать ключ в TPM (разово)

```bash
tpm2_ptool init
tpm2_ptool addtoken --pid=1 --label=ssh --userpin= --sopin=
tpm2_ptool addkey --label=ssh --userpin= --algorithm=ecc256
ssh-keygen -D /run/current-system/sw/lib/libtpm2_pkcs11.so
```

`ssh-keygen -D` выводит публичную часть ключа (строка вида `ecdsa-sha2-nistp256 AAAA...`). Пустые
PIN (`--userpin=`/`--sopin=`) — это и есть «без ручных действий».

## Шаг 6 — добавить публичный ключ в authorized_keys

Файл root-owned, путь `/etc/ssh/authorized_keys.d/neg` (модуль использует `%u` → имя вызывающего
пользователя):

```bash
# вставить строку из ssh-keygen -D:
sudo tee -a /etc/ssh/authorized_keys.d/neg
sudo chown root:root /etc/ssh/authorized_keys.d/neg
sudo chmod 0644 /etc/ssh/authorized_keys.d/neg
```

Не кладите файл в домашнюю директорию — это дыра ([nixpkgs#31611]).

## Шаг 7 — проверить

```bash
ssh-add -s /run/current-system/sw/lib/libtpm2_pkcs11.so   # вручную, для проверки
ssh-add -l                                                # ключ виден в агенте
sudo -k && sudo true                                      # пароль не спрашивается
```

После перелогина ключ подхватит `tpm2-ssh-add.service` — `ssh-add` руками больше не нужен.

## Откат

```nix
features.security.tpmSudo.enable = false;
```

```bash
nh os switch /etc/nixos#odin --option substitute false
```

TPM снова отключён: модули в blacklist, `/dev/tpmrm0` не создаётся, `sudo` работает по паролю, как
раньше.

## Безопасность и компромиссы

- Ключ неэкспортируем и привязан к железу — украсть файл ключа невозможно.
- **Пустой PIN** означает: TPM подписывает любому процессу в группе `tss` (т.е. процессам
  пользователя `neg`). Это защита от *кражи ключа*, но не от *злоупотребления из вашей же сессии* —
  как и любой беспарольный sudo.
- Для строже: задать PIN (`--userpin=...`), тогда `ssh-add -s` спросит его один раз за сессию (и
  `tpm2-ssh-add.service` для автозагрузки не подойдёт — нужен ручной `ssh-add -s`). Требует одного
  действия руками.
