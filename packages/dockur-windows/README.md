# dockur-windows — auto-provisioning Windows VM (dockur/windows)

Custom image based on dockur/windows: during Windows setup the proxy is configured automatically
(Edge policy + WinINET + env) and installers from `oem/installers/` are installed.

## Mechanism

dockur copies the mounted `/oem` onto the Windows disk at `C:\OEM` and runs `C:\OEM\install.bat`
during setup (the built-in OEM_SCRIPT hook). `install.bat` invokes `setup.ps1`, which:

1. sets the system WinINET proxy (`HKLM` → `192.168.2.88:10812`) — for GLM and GUI apps;
1. sets the Edge policy (`HKLM\Software\Policies\Microsoft\Edge` → `socks5://192.168.2.88:10811`);
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
(192.168.2.87), so the host replies to the UDP handshake "to itself". Instead there is a one-way TCP
bridge, with the connection initiated by the VM (the only bidirectional host↔VM channel):

1. On the host, the user service `glm-midi-relay` listens on `0.0.0.0:9003` (for the VM) and
   `127.0.0.1:9004` (for the local `glm-midi`).
1. Inside the VM, `oem/glm-midi-bridge.ps1` (PowerShell) runs: it connects to `192.168.2.88:9003`,
   receives 3-byte MIDI messages (B0 cc val) and sends them to the rtpMIDI port (winmm `midiOut`) →
   GLM.
1. `glm-midi volume 60` / `mute` / `dim` / `power` on the host.

No port forwarding is needed in `docker run` for the bridge (the VM reaches out on its own). The
bridge script is placed in `C:\OEM\` during setup (or downloaded from
`http://192.168.2.88:8010/glm-midi-bridge.ps1`).

## Verification

After Windows boots: the host should show the VM's proxy connections (`ss -tnp | grep 10812`), and
inside the VM — `C:\OEM\provisioned.txt` and logs.

## Pitfall: .88 alias inside the container

pasta (`--config-net`) copies the host addresses into the container — including the `192.168.2.88`
alias when it already exists on net1. The container then treats .88 as its own address and answers
`Connection refused` to itself on 10811/10812 (the VM goes the same way through passt). After every
container re-creation remove it:

```bash
docker exec windows ip addr del 192.168.2.88/24 dev net1
```

(Or add the .88 alias on the host only AFTER the container has started.)
