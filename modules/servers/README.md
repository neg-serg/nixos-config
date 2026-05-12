# Servers Module

Server profiles and service configuration.

## Enable Services

```nix
profiles.services.<name>.enable = true;
# or
servicesProfiles.<name>.enable = true;
```

## Available Services

| Service | Port | Description | |---------|------|-------------| | `openssh` | 22/TCP | SSH server
| | `mpd` | 6600/TCP | Music Player Daemon | | `jellyfin` | 8096/TCP | Media streaming | |
`adguardhome` | 53, 3000 | DNS filtering | | `unbound` | 5353/TCP | DNS resolver | | `duckdns` | - |
Dynamic DNS |

## DNS Stack

```
Apps → systemd-resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) → Unbound (127.0.0.1:5353)
```

## DNS Healthcheck

```bash
systemctl status adguardhome unbound systemd-resolved
ss -lntup | rg ':53|:5353'
resolvectl status
resolvectl query example.com
```

## Policy

- No eval warnings — modules must not emit `warnings`, `trace`, or `lib.warn`
