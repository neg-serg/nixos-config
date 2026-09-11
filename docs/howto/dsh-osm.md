# dsh-osm — OpenStreetMap in dsh

The `dsh-osm` plugin adds four tools to the DeepSeek Harness (web profile) on top of the free public
OSM APIs, a skill with etiquette rules, and an interactive Leaflet map right in the chat.

## Features

| Tool           | What it does                                                  | Service                          |
| -------------- | ------------------------------------------------------------- | -------------------------------- |
| `osm_geocode`  | place name/address → coordinates                              | Nominatim (+ Photon as fallback) |
| `osm_reverse`  | coordinates → address                                         | Nominatim (+ Photon as fallback) |
| `osm_overpass` | POI/data via Overpass QL (`node["amenity"="cafe"](around:…)`) | overpass-api.de                  |
| `osm_route`    | route between points (driving/walking/cycling)                | OSRM (router.project-osrm.org)   |

Each tool returns a textual summary for the model plus a map descriptor (`presentationMeta`), which
the web GUI renders as an interactive card: markers for geocoding/POI, a polyline for routes. In
TUI/headless only the textual summary works. The map is replayed from the saved descriptor — without
repeated API requests.

## How it is wired up

- Plugin code: `modules/user/nix-maid/apps/dsh-osm/` (`package.json`, `lib/index.js` — the server
  half, `lib/tools.js` — the tools, `lib/client.js` — the Leaflet card, `assets/osm-skill.md` — the
  skill, `assets/leaflet/` — vendored Leaflet 1.9.4 without CDN).
- Installation: the module `modules/user/nix-maid/apps/dsh-osm.nix` copies the plugin into
  `~/.dsh/profiles/web/node_modules/dsh-osm/` (as a plain dir, without pnpm — the `@deepseek-ai`
  symlink does not survive pnpm writes) and appends the row `- insert: [{ id: osm, name: dsh-osm }]`
  to `~/.dsh/profiles/web/cordis.patch.yml`.
- The server side serves Leaflet at `/osm/leaflet/*` (a prefix route of the webServer; a prefix
  without a trailing slash — the matcher appends the `/` itself).
- dsh runs under systemd (`dsh.service`), so after changes you need
  `systemctl --user restart dsh.service`.

## Important

- Plugin files are copied into the profile **only if they are not already there** (the repo pattern
  is that local edits survive rebuilds). To apply a changed version from the module: remove
  `~/.dsh/profiles/web/node_modules/dsh-osm` and restart dsh.
- The public OSM APIs are free but strictly rate-limited: the plugin keeps ~1 request/s to
  Nominatim/Overpass (queued), sends a proper User-Agent, and explains 429/403/504 errors.
- If Nominatim is unavailable (regional network), geocoding automatically falls back to Photon
  (`photonBase`); disable the fallback with `photonBase: ""`.
- Heavy/production load is better moved to self-hosted instances — the base URLs are configured in
  the plugin's `Config` (`nominatimBase`, `overpassBase`, `osrmBase`).
