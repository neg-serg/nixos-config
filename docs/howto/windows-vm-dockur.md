# Dockur Windows VM on odin: GLM USB passthrough and proxy

Windows 11 runs in a **dockur/windows** container (QEMU/KVM); the disk lives in a podman volume (survives
container re-creation). Access: RDP `127.0.0.1:3389` (user from `USERNAME`, password from
`PASSWORD`) or the noVNC/KasmVNC web UI `http://127.0.0.1:8006`.

## Running the container

The disk lives in the podman volume `f1047db9589f…` (bind into `/storage`). Re-creation command:

```bash
docker run -d --name windows \
  -v f1047db9589f2c0f4f8f31b6b4b4eeca2e4954d482ed0b8ed605cd3eb9033dc8:/storage \
  -v /dev/bus/usb:/dev/bus/usb \
  --device=/dev/kvm \
  --device /dev/bus/usb \
  --cap-add NET_ADMIN \
  -p 8006:8006 -p 3389:3389/tcp -p 3389:3389/udp \
  -e VERSION="win11" -e USERNAME="neg" -e PASSWORD="password" \
  -e RAM_SIZE="16G" -e DISK_SIZE="120G" -e CPU_CORES="2" \
  -e TPM_VERSION="2.0" -e SECURE_BOOT="Y" \
  -e ARGUMENTS="-device usb-host,vendorid=0x1781,productid=0x0e39" \
  --stop-timeout 120 \
  docker.io/dockurr/windows
```

Key flags:

- `-v f1047db9…:/storage` — persistent disk (Windows is installed once; re-creations do not lose it).
- `-v /dev/bus/usb:/dev/bus/usb` — **live** USB bind-mount. `--device /dev/bus/usb` is NOT enough:
  podman copies the nodes at start (a snapshot) and does not see devices plugged in later.
- `-e ARGUMENTS="-device usb-host,…"` — USB device passthrough into QEMU (hotplug analogue —
  `device_add usb-host,vendorid=…,productid=…` via the monitor).

### Gotchas: memlock (vfio dma_map ENOMEM)

With iGPU passthrough (vfio-pci 1002:13c0) QEMU pins ~14 GB of guest RAM for DMA in the vfio container at
start. If the RLIMIT_MEMLOCK of the QEMU process is below that, the container crashes immediately:

```
qemu-system-x86_64: -device vfio-pci,host=0000:7c:00.0: vfio 0000:7c:00.0: failed to setup
container for group 30: memory listener initialization failed: Region pc.ram:
vfio_container_dma_map(...) = -12 (Cannot allocate memory)
```

The limit is raised in hardware.nix at three levels (all three are needed):

1. `systemd.settings.Manager.DefaultLimitMEMLOCK = "infinity"` — systemd (system); applies to
   system services, including `user@.service` when it is (re)started.
1. `systemd.user.settings.Manager.DefaultLimitMEMLOCK = "infinity"` — the user manager (user
   units: dsh web, terminals under systemd --user).
1. `security.pam.loginLimits` for neg — fresh login sessions (PAM).

Important: neither the systemd defaults nor pam_limits retro-fit already-running sessions — they are read
at manager start/login time. Sessions started before the config was applied (e.g. after a reboot with a
new kernel that enabled vfio) keep the old hard limit (4 GiB) and `docker start windows` fails with
ENOMEM even though the config is already “correct”. Fixable without a reboot (as root):

```bash
# raise the limit for every live process of the needed cgroups (manager + sessions):
for cg in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service \
           /sys/fs/cgroup/user.slice/user-1000.slice/session-3.scope; do
  while read -r p; do sudo prlimit --pid "$p" --memlock=unlimited:unlimited; done < "$cg/cgroup.procs"
done
# (user@1000.service: recurse into the nested cgroups — the parent cgroup.procs is empty)
```

After a reboot everything is picked up by itself (user@.service inherits infinity from the system default,
sessions from pam). Check: `grep -i locked /proc/<pid qemu>/limits` → `unlimited`.

## Genelec GLM (Gnet Adapter) USB passthrough

Device: `1781:0e39` (Bus 009). Three gotchas without which the “passthrough is not visible”:

1. **Container user namespace**: root inside = `nobody` on the host. udev creates USB nodes with
   `0664 root:root` permissions → the container gets `EPERM` and cannot open the device (QEMU shows a
   fake `USB Host Device` at 1.5 Mb/s instead of `Gnet Adapter` at 12 Mb/s). Fixed by a udev rule (in
   `hosts/odin/hardware.nix`):
   ```
   SUBSYSTEM=="usb", ATTR{idVendor}=="1781", ATTR{idProduct}=="0e39", MODE="0666"
   ```
   Runtime check: `chmod 666 /dev/bus/usb/009/004` (after re-plugging, the node may change).
1. **USB snapshot**: `--device /dev/bus/usb` copies the nodes at start. The live variant is a bind-mount
   `-v /dev/bus/usb:/dev/bus/usb` (see the command above).
1. **udev may not create a node** for unusual HID devices: sysfs exists, `/dev/bus/usb` does not. Trigger:
   `sudo udevadm trigger --attr-match=idVendor=1781`.

Passthrough check (deterministic, without a GUI):

```bash
printf 'info usb\n' | timeout 5 docker exec -i windows nc -U /run/shm/monitor.sock
# Expected: Device 0.2, Port 2, Speed 12 Mb/s, Product Gnet Adapter
# Bad:      Device 0.0, Port 2, Speed 1.5 Mb/s, Product USB Host Device
```

## VM network: IP conflict and host alias

pasta/passt give the VM **the same IP as the host** (`192.168.2.87`) — the VM physically cannot reach
the host on its main address. Therefore an **alias `192.168.2.88`** was added on net1 (declaratively in
`hosts/odin/networking.nix` — Address as a list):

```nix
Address = [
  "192.168.2.87/24"
  "192.168.2.88/24"
];
```

All VM proxies go through `192.168.2.88`. (A runtime alias `ip addr add …` is washed away by networkd —
that is why it lives in the config.)

## Proxy for the VM (inside the host sing-box)

Two passwordless inbounds, added to the generator `packages/local-bin/bin/proxy` (tags `in-lan-vm` /
`in-lan-vm-http`):

| Port    | Type          | Purpose                                                             |
| ------- | ------------- | ------------------------------------------------------------------- |
| `10811` | SOCKS5        | Chromium/Edge (cannot do SOCKS authentication)                      |
| `10812` | HTTP CONNECT  | WinINET system proxy — GLM and other GUI apps (WinINET cannot do SOCKS) |

Firewall (`modules/system/net/firewall.nix`): both ports are allowed only from private ranges
(`10/8`, `172.16/12`, `192.168/16`), as is `10810`.

## Windows setup inside the VM

- **Edge** (browser only) — the policy overrides everything else:
  ```
  reg add "HKCU\Software\Policies\Microsoft\Edge" /v ProxyMode /t REG_SZ /d fixed_servers /f
  reg add "HKCU\Software\Policies\Microsoft\Edge" /v ProxyServer /t REG_SZ /d "socks5://192.168.2.88:10811" /f
  ```
- **WinINET system proxy** (GLM and other GUI apps; Edge is unaffected):
  ```
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "192.168.2.88:10812" /f
  ```
- **Console utilities** (new windows):
  `setx ALL_PROXY/HTTPS_PROXY/HTTP_PROXY "socks5h://192.168.2.88:10811"`.

## Checks and debugging

- Exit IP via the proxy ≠ direct:
  ```bash
  curl -s http://api.ipify.org                      # direct: 178.237.248.44
  curl -s -x http://192.168.2.88:10812 http://api.ipify.org   # node: 193.29.139.195
  ```
- The VM really does go through the proxy (live VM connections via passt):
  ```bash
  ss -tnp | grep 10812   # ESTAB 192.168.2.87:… -> 192.168.2.88:10812 (passt.avx2)
  ```
- Proxy log: `journalctl --user -u sing-box-proxy`. DNS timeouts
  (`lookup failed … context deadline exceeded`, DoH 1.1.1.1) are transient and need no action.
- **GLM “Cloud connection error” / 400**: the Genelec cloud (`glmcloud.genelec.com`) is reachable both
  directly and through the proxy (curl → 200). A 400 is a Genelec API/account issue, not the network or
  the proxy.

## MIDI control of GLM from Linux (TCP bridge → rtpMIDI → GLM 5)

GLM 5 supports MIDI remote (volume/mute/dim/power). Chain: `glm-midi` (CLI) → `glm-midi-relay`
(user service, TCP) → bridge in the VM (`glm-midi-bridge.ps1`, TCP client) → **rtpMIDI** (a virtual
MIDI port in Windows) → GLM 5.

Why a TCP bridge and not RTP-MIDI: the VM shares the host IP (192.168.2.87 via pasta), so the host
replies to the RTP-MIDI UDP handshake go “to itself” and get lost — a bidirectional protocol physically
does not work in this topology (rtpmidid/rtpMIDI stay in the repo as a fallback but are not used). The
only bidirectional host↔VM channel is a TCP connection initiated by the VM itself (VM outbound traffic
via passt works; replies come back — like through the .88:10812 proxy). Hence the bridge in the VM
connects to the host on its own.

### Linux (odin)

- `packages/local-bin/bin/glm-midi-relay` — Python daemon: listens on `0.0.0.0:9003` (the bridge from
  the VM connects here) and `127.0.0.1:9004` (where `glm-midi` sends), forwarding packets into the
  current VM connection. User service `glm-midi-relay` (`modules/user/nix-maid/sys/user-services.nix`).
- `packages/local-bin/bin/glm-midi` — CLI: sends 3 bytes (B0 cc val) to `127.0.0.1:9004`.
- Check: `systemctl --user status glm-midi-relay`; `ss -tlnp | grep -E '9003|9004'`.

### VM (Windows)

- `packages/dockur-windows/oem/glm-midi-bridge.ps1` — PowerShell bridge: connects to
  `192.168.2.88:9003`, receives MIDI messages and sends them to the rtpMIDI port (winmm `midiOut`);
  on a drop it reconnects every 2 s. Launch:
  `powershell -ExecutionPolicy Bypass -File C:\OEM\glm-midi-bridge.ps1` (or download it from
  `http://192.168.2.88:8010/glm-midi-bridge.ps1` and run).
- In rtpMIDI, leave the GLM listening port as MIDI-in; the rtpMIDI network session is no longer needed.

### GLM 5 MIDI CC map (from VOL20toGenelecGLM/CONSTANTS.md)

| CC      | Function                                        |
| ------- | ------------------------------------------------ |
| 20      | absolute volume 0..127 (dB = value − 127)        |
| 21 / 22 | volume + / −                                     |
| 23      | Mute (toggle)                                    |
| 24      | Dim (toggle)                                     |
| 28      | Power (toggle)                                   |

In GLM: Settings → MIDI → “Enable GLM MIDI interface”; Mute/Dim/Power are in Toggle mode.

### Container

No port forwarding is needed for the bridge: the VM initiates the outbound TCP connection itself (as for
the proxy).

### Usage

```bash
glm-midi volume 60        # volume 0..127
glm-midi volume -18dB     # or in dB
glm-midi mute             # toggle
glm-midi dim              # toggle
glm-midi power            # toggle
glm-midi vol+ 3           # +3 steps
```

Tidal/SuperCollider: call `glm-midi` from code (SC: `SystemCmd("glm-midi mute")`, Tidal:
`SystemCmd`) or send CC to `127.0.0.1:9004` (3 bytes B0 cc val per packet).

## Affected files

- `hosts/odin/default.nix` — flag `features.net.proxy.enable`
- `hosts/odin/networking.nix` — alias `192.168.2.88/24`
- `hosts/odin/hardware.nix` — Genelec GLM udev rule (0666)
- `modules/system/net/firewall.nix` — ports 10811/10812, 5010/5011 (RTP-MIDI, fallback), 9003
  (MIDI bridge)
- `packages/local-bin/bin/glm-midi-relay` + `glm-midi` — MIDI bridge (relay) and CLI
- `packages/dockur-windows/oem/glm-midi-bridge.ps1` — bridge in the VM
- `packages/local-bin/bin/proxy` — the inbounds `in-lan-vm` (SOCKS 10811) and `in-lan-vm-http` (HTTP
  10812\)

## GLM alternative: the glm-osc OSC bridge (adapter on the host)

Since 2026-08-30 everyday monitor control runs WITHOUT the official GLM: the USB adapter (1781:0e39)
lives on the host, the `glm-osc` service (Python genlc + python-osc) listens on UDP 127.0.0.1:9000 and
drives the monitors over OSC. The VM with GLM is needed only for calibration (see below).

OSC map:

```
/glm/volume <dB>          # absolute volume
/glm/volume/ratio <0..1>  # as a linear ratio
/glm/volume/up|down <dB>  # relative (stateful)
/glm/mute <0|1> | /glm/mute/toggle
/glm/power <1|0|2> | /glm/power/toggle   # 2 = toggle
/glm/led <green|red|yellow|off> [pulse]
/glm/status | /glm/discover   # replies in /glm/status/reply and /glm/discover/reply
```

Example from Tidal/SuperCollider: `NetAddr("127.0.0.1", 9000).sendMsg("/glm/volume", -20)`; from Tidal
via `osc` patterns (`Sound.Tidal.OSC`). State (last volume, mute, power) is stored in
`~/.local/state/glm-osc-state.json`.

Important:

- **Do not run GLM (VM) and glm-osc at the same time** — the adapter is single-master.
- genlc does NOT support dim and input selection (0x0D/0x40) — only volume/mute/power/LED/status.
- Calibration and input selection: start the VM (the adapter goes into passthrough), do it in GLM, Store
  settings (calibration is stored ON THE MONITORS), shut down the VM — the adapter returns to the host,
  control goes through glm-osc again.
- udev: hardware.nix binds usbhid to the adapter (otherwise there is no /dev/hidraw and genlc does not
  see the device).
