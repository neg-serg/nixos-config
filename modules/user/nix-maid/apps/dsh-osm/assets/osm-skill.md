# OSM (OpenStreetMap) — osm\_\* tools

You have four tools backed by the free public OSM services. They return text summaries and, in the
web GUI, render an interactive map card automatically — you do not need to draw maps yourself.

## Tool choice

| Task                                                               | Tool           |
| ------------------------------------------------------------------ | -------------- |
| Place name / address → coordinates                                 | `osm_geocode`  |
| Coordinates → address / place                                      | `osm_reverse`  |
| POIs and features ("cafes near X", "all pharmacies in a district") | `osm_overpass` |
| Directions between two points                                      | `osm_route`    |

## Conventions

- **Coordinates** are WGS84. In `osm_route`, endpoints may be place names (the tool geocodes them)
  or `"lat, lon"` strings with a comma, e.g. `"55.7539, 37.6208"`.
- **Geocoding quality**: use local-language names for best results ("Красная площадь" or "Red
  Square" beat transliterations like "Krasnaya Ploshchad"). Geocoding tries Nominatim first and
  automatically falls back to Photon (also OSM-based) when the public Nominatim instance is
  unreachable or rate-limited, so results can differ slightly between the two.
- `osm_geocode` returns several candidates; the first is usually the best. Use `countrycodes` to
  disambiguate (e.g. `ru` vs `de`) and `viewbox` `"lon1,lat1,lon2,lat2"` to bias a search toward a
  region.
- `osm_reverse` zoom: 18 = building-level (default), 10–14 = suburb/city, 4–8 = country.

## Overpass QL basics

`osm_overpass` runs an Overpass QL body. You may omit the `[out:json]` header — the tool adds
`[out:json][timeout:N]` itself. Common patterns:

- Around a point (meters): `node["amenity"="cafe"](around:1000,55.7558,37.6173); out;`
- In a bounding box: `node["shop"](51.5,-0.12,51.52,-0.10); out;`
- By name: `node["name"~"Hermitage",i]; out;`
- To get way geometry back use `out geom;` — ways then render as lines on the map.

Keep queries **bounded**: prefer `(around:…)` or a bbox over full-planet scans, keep the default
`[timeout:25]`, and let the tool's default limits stand. The public Overpass endpoint is shared by
thousands of users.

## Public API etiquette (the tools enforce this; know it anyway)

- **Nominatim** (geocode/reverse): max **1 request/second**, always send a proper User-Agent (the
  plugin does), no bulk downloads. The tool queues requests so parallel calls stay polite.
- **Overpass**: the public endpoint is rate-limited and may return HTTP 429 — wait and retry, do not
  hammer it.
- **OSRM** (route): the public demo server is for light use; prefer `walking`/`cycling`/`driving` as
  needed, keep route requests modest.
- All of these are community-funded free services. If a user needs heavy or production use, suggest
  self-hosting (the plugin's base URLs are configurable) instead of hammering the public instances.

## Map card

Each tool attaches a map descriptor to its result. In the web GUI this renders as an interactive
Leaflet card: geocode/reverse show markers, overpass shows markers (and simple way lines), route
shows a polyline with start (green) and end (red) markers. In TUI/headless you only get the text
summary — phrase answers so they are complete without the map.
