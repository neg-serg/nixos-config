# dockur-windows — auto-provisioning Windows VM (dockur/windows)

Custom image based on dockur/windows: during Windows setup the proxy is configured automatically
(Edge policy + WinINET + env) and installers from `oem/installers/` are installed.

## Mechanism

dockur copies the mounted `/oem` onto the Windows disk at `C:\OEM` and runs `C:\OEM\install.bat`
during setup (the built-in OEM_SCRIPT hook). `install.bat` invokes `setup.ps1`, which:

1. sets the system WinINET proxy (`HKLM` → `192.168.0.11:10812`) — for GLM and GUI apps;
1. copies that value into every loaded user hive (`proxy-sync.ps1`, logon hook `GLMProxySync`) —
   WinINET reads HKCU before HKLM, so a later host LAN move would otherwise leave the user hive on
   the old alias;
1. sets the Edge policy (`HKLM\Software\Policies\Microsoft\Edge` → `socks5://192.168.0.11:10811`);
1. writes the env vars ALL_PROXY/HTTPS_PROXY/HTTP_PROXY (machine-wide);
1. silently installs everything from `oem/installers/` (Inno: /VERYSILENT, NSIS: /S, MSI: /qn);
1. writes the `C:\OEM\provisioned.txt` marker and logs to `C:\OEM\install.log`.

## Usage

Option A — custom image:

```bash
cd packages/dockur-windows
docker build -t dockur-windows-auto .
# then in docker run use dockur-windows-auto instead of docker.io/dockurr/windows
```

Option B — no image rebuild (fast iteration):

```bash
docker run -d --name windows \
  -v <disk volume>:/storage \
  -v /etc/nixos/packages/dockur-windows/oem:/oem \
  ... (other flags as in docs/howto/windows-vm-dockur.md) \
  docker.io/dockurr/windows
```

## Installers

Put the needed .exe/.msi into `oem/installers/` before setup starts:

- `rtpMIDI` (tobias-erichsen.de) — virtual MIDI port for GLM MIDI (the network part is not used, see
  the MIDI bridge below);
- `GLM` (MyGenelec) — the Genelec software itself (only if it supports silent install; otherwise
  install it manually after first boot).

## MIDI bridge Linux → VM (GLM 5 MIDI-remote)

RTP-MIDI (rtpmidid ↔ rtpMIDI) does not work in this topology: the VM shares the host IP
(192.168.0.10), so the host replies to the UDP handshake "to itself". Instead there is a one-way TCP
bridge, with the connection initiated by the VM (the only bidirectional host↔VM channel):

1. On the host, the user service `glm-midi-relay` listens on `0.0.0.0:9003` (for the VM) and
   `127.0.0.1:9004` (for the local `glm-midi`).
1. Inside the VM, `oem/glm-midi-bridge.ps1` (PowerShell) runs: it connects to `192.168.0.11:9003`,
   receives 3-byte MIDI messages (B0 cc val) and sends them to the rtpMIDI port (winmm `midiOut`) →
   GLM.
1. `glm-midi volume 60` / `mute` / `dim` / `power` on the host.

No port forwarding is needed in `docker run` for the bridge (the VM reaches out on its own). The
bridge script is placed in `C:\OEM\` during setup (or downloaded from
`http://192.168.0.11:8010/glm-midi-bridge.ps1`).

## Verification

After Windows boots: the host should show the VM's proxy connections (`ss -tnp | grep 10812`), and
inside the VM — `C:\OEM\provisioned.txt` and logs.

## After an uplink move (host re-addressed)

`setup.ps1` runs only during provisioning, so when the host alias changes (`.88` → `.11` on
2026-10-15) apply the new value in the running VM once — `proxy-sync.ps1 -Proxy` writes HKLM and
every user hive:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OEM\proxy-sync.ps1 -Proxy 192.168.0.11:10812
```

Without it the user hive keeps the old alias and every WinINET app (OneDrive, GLM) sits in
`SYN-SENT` to the dead address.

## Pitfall: .11 alias inside the container

pasta (`--config-net`) copies the host addresses into the container — including the `192.168.0.11`
alias when it already exists on net1. The container then treats .11 as its own address and answers
`Connection refused` to itself on 10811/10812 (the VM goes the same way through passt) — and on 9003
for the MIDI bridge, which then holds a dead TCP connection while still printing
`connected to host relay`, so every CC silently disappears. This is no longer a manual step:
`glm-vm-netfix` removes the alias, and `windows-vm.service` runs it as `ExecStartPost` while
`glm-adapter` calls it after the VM restarts it performs itself. After any other container (re)start
run it by hand:

```bash
glm-vm-netfix windows           # script form
podman exec windows ip addr del 192.168.0.11/24 dev net1   # what it does
```

(Or add the .11 alias on the host only AFTER the container has started.)
