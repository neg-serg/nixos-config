# Roles: Quick Reference

## Enable Roles

```nix
roles.workstation.enable = true;  # Desktop defaults
roles.homelab.enable = true;      # Self-hosting defaults
roles.media.enable = true;        # Media servers
roles.server.enable = true;       # Headless/server defaults
```

## Role Features

| Role | Features | |------|----------| | `workstation` | Performance profile, SSH, Avahi | |
`homelab` | Security profile, DNS, SSH, MPD | | `media` | Jellyfin, MPD, Avahi, SSH | | `server` |
Headless, smartd by default |

## Override Services

```nix
profiles.services.<name>.enable = false;
# Example:
profiles.services.jellyfin.enable = false;
```

## Typical Next Steps

- **Workstation**: Adjust games in `profiles.games.*` and `modules/user/games`
- **Homelab**: Set DNS rewrites in `servicesProfiles.adguardhome.rewrites`
- **Media**: Set media paths/ports for MPD
