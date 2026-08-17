/**
 * dsh-osm — model-facing tools.
 *
 * Four tools over the free public OSM services:
 *   osm_geocode   — Nominatim search (place name → coordinates)
 *   osm_reverse   — Nominatim reverse (coordinates → address)
 *   osm_overpass  — Overpass QL query (POI / feature extraction)
 *   osm_route     — OSRM routing (driving / walking / cycling)
 *
 * Design notes:
 *  - All requests go out from the host (Node), never from the browser, so
 *    CORS is a non-issue and rate limits + User-Agent policy are enforced in
 *    one place. The browser half only ever loads map tiles and the plugin's
 *    own Leaflet assets.
 *  - Every tool returns a compact text summary for the model plus a
 *    `presentationMeta` descriptor `{ kind: 'osm-map', ... }` that the web
 *    client renders as an interactive Leaflet card. The descriptor is
 *    persisted with the session log, so replay re-renders the same map from
 *    logged data — no live API calls during replay.
 *  - Public OSM APIs are community-funded: stay polite (see assets/osm-skill.md).
 *
 * @module dsh-osm/tools
 */

import { defineTool } from '@deepseek-ai/dsh-tools'
import { createRateLimiter } from './rate-limit.js'

const DEFAULT_UA = 'dsh-osm/0.1 (DeepSeek Harness OSM plugin; interactive light use)'

/** Tag priority for Overpass subtitles — first present tag wins. */
const TAG_PRIORITY = [
  'amenity', 'shop', 'tourism', 'leisure', 'historic', 'natural',
  'highway', 'place', 'landuse', 'building', 'cuisine', 'railway', 'waterway',
]

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

function truncate(value, max) {
  if (typeof value !== 'string') return String(value)
  return value.length > max ? `${value.slice(0, max - 1)}…` : value
}

function toNum(value) {
  const n = typeof value === 'string' ? Number(value) : value
  return Number.isFinite(n) ? n : NaN
}

/** Parse "lat, lon" (or "lat,lon") into [lat, lon], or null. */
function parseCoords(input) {
  const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(input ?? ''))
  if (!match) return null
  const lat = Number(match[1])
  const lon = Number(match[2])
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null
  return [lat, lon]
}

function decimate(points, max) {
  if (points.length <= max) return points
  const stride = Math.ceil(points.length / max)
  const out = []
  for (let i = 0; i < points.length; i += stride) out.push(points[i])
  if (out[out.length - 1] !== points[points.length - 1]) out.push(points[points.length - 1])
  return out
}

/** Bounding box [[minLat, minLon], [maxLat, maxLon]] over all coordinates. */
function boundsOf(coords) {
  if (coords.length === 0) return undefined
  let minLat = Infinity
  let minLon = Infinity
  let maxLat = -Infinity
  let maxLon = -Infinity
  for (const [lat, lon] of coords) {
    if (lat < minLat) minLat = lat
    if (lat > maxLat) maxLat = lat
    if (lon < minLon) minLon = lon
    if (lon > maxLon) maxLon = lon
  }
  return [[minLat, minLon], [maxLat, maxLon]]
}

/** Format meters / seconds into a compact human line. */
function humanDistance(meters) {
  return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.round(meters)} m`
}

function humanDuration(seconds) {
  if (seconds >= 3600) {
    const h = Math.floor(seconds / 3600)
    const m = Math.round((seconds % 3600) / 60)
    return m > 0 ? `${h} h ${m} min` : `${h} h`
  }
  return `${Math.round(seconds / 60)} min`
}

/** Shrink a meta descriptor until it fits maxBytes (progressive lossy trim). */
function capMeta(meta, maxBytes) {
  let candidate = meta
  for (let pass = 0; pass < 6; pass += 1) {
    const serialized = JSON.stringify(candidate)
    if (serialized.length <= maxBytes) return candidate
    const copy = { ...candidate }
    // Drop marker subtitles first, then markers, then polyline detail.
    if (Array.isArray(copy.markers)) {
      copy.markers = copy.markers.map((m) => ({ lat: m.lat, lon: m.lon, title: truncate(m.title ?? '', 80) }))
    }
    if (Array.isArray(copy.markers) && copy.markers.length > 25) {
      copy.markers = copy.markers.slice(0, 25)
    }
    if (Array.isArray(copy.polyline)) {
      copy.polyline = decimate(copy.polyline, Math.max(64, Math.floor((copy.polyline?.length ?? 0) / 2)))
    }
    if (Array.isArray(copy.polylines)) {
      copy.polylines = copy.polylines.map((line) => decimate(line, Math.max(64, Math.floor((line?.length ?? 0) / 2))))
    }
    candidate = copy
  }
  // Last resort: coordinates only.
  return { kind: 'osm-map', tool: meta.tool, label: truncate(meta.label ?? '', 120) }
}

/**
 * Narrow an untrusted persisted `tool/result` meta value to the map
 * descriptor, or undefined when it does not match the wire contract.
 */
export function osmMetaFrom(meta) {
  if (typeof meta !== 'object' || meta === null) return undefined
  const record = meta
  if (record.kind !== 'osm-map') return undefined
  if (typeof record.tool !== 'string' || typeof record.label !== 'string') return undefined
  const out = { kind: 'osm-map', tool: record.tool, label: record.label }
  if (typeof record.center === 'object' && record.center !== null) {
    const [lat, lon] = [toNum(record.center[0]), toNum(record.center[1])]
    if (Number.isFinite(lat) && Number.isFinite(lon)) out.center = [lat, lon]
  }
  if (Array.isArray(record.markers)) {
    const markers = []
    for (const m of record.markers) {
      if (typeof m !== 'object' || m === null) continue
      const lat = toNum(m.lat)
      const lon = toNum(m.lon)
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue
      markers.push({
        lat,
        lon,
        title: typeof m.title === 'string' ? m.title : '',
        ...typeof m.subtitle === 'string' ? { subtitle: m.subtitle } : {},
        ...typeof m.color === 'string' ? { color: m.color } : {},
      })
    }
    if (markers.length > 0) out.markers = markers
  }
  if (Array.isArray(record.polyline)) {
    const points = []
    for (const p of record.polyline) {
      if (typeof p !== 'object' || p === null) continue
      const lat = toNum(p[0])
      const lon = toNum(p[1])
      if (Number.isFinite(lat) && Number.isFinite(lon)) points.push([lat, lon])
    }
    if (points.length > 0) out.polyline = points
  }
  if (Array.isArray(record.polylines)) {
    const polylines = []
    for (const line of record.polylines) {
      if (!Array.isArray(line)) continue
      const points = []
      for (const p of line) {
        if (typeof p !== 'object' || p === null) continue
        const lat = toNum(p[0])
        const lon = toNum(p[1])
        if (Number.isFinite(lat) && Number.isFinite(lon)) points.push([lat, lon])
      }
      if (points.length >= 2) polylines.push(points)
    }
    if (polylines.length > 0) out.polylines = polylines
  }
  if (typeof record.bounds === 'object' && record.bounds !== null) {
    const sw = record.bounds[0]
    const ne = record.bounds[1]
    if (Array.isArray(sw) && Array.isArray(ne)) {
      const swLat = toNum(sw[0])
      const swLon = toNum(sw[1])
      const neLat = toNum(ne[0])
      const neLon = toNum(ne[1])
      if (Number.isFinite(swLat) && Number.isFinite(swLon) && Number.isFinite(neLat) && Number.isFinite(neLon)) {
        out.bounds = [[swLat, swLon], [neLat, neLon]]
      }
    }
  }
  return out
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

/** Transport-level failure (network, timeout, bad payload) — candidates for a geocoder fallback. */
class OsmTransportError extends Error {}

/** The API answered but refused: 429 / 403 / 5xx / application error. */
class OsmHttpError extends Error {
  constructor(message, status) {
    super(message)
    this.status = status
  }
}

/**
 * Fetch JSON from a public OSM endpoint with a polite UA, a hard timeout,
 * caller cancellation, and HTTP error classification.
 */
async function fetchJson(url, { signal, timeoutMs, userAgent, method = 'GET', body, form }) {
  const timeoutSignal = AbortSignal.timeout(timeoutMs)
  const combined = signal !== undefined ? AbortSignal.any([signal, timeoutSignal]) : timeoutSignal
  let response
  try {
    response = await fetch(url, {
      method,
      signal: combined,
      headers: {
        'user-agent': userAgent,
        ...form !== undefined ? { 'content-type': 'application/x-www-form-urlencoded' } : {},
      },
      ...body !== undefined ? { body } : {},
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new OsmTransportError(`OSM API request timed out after ${Math.round(timeoutMs / 1000)} s — try again or simplify the query`)
    }
    throw new OsmTransportError(`OSM API unreachable: ${error?.message ?? String(error)}`)
  }
  if (response.status === 429) {
    throw new OsmHttpError('OSM API rate limit (HTTP 429) — the public endpoints allow ~1 request/second; wait a moment and retry', 429)
  }
  if (response.status === 403) {
    throw new OsmHttpError('OSM API refused the request (HTTP 403) — check the query and that a proper User-Agent is sent', 403)
  }
  if (response.status === 504) {
    throw new OsmHttpError('OSM API timed out upstream (HTTP 504) — simplify the query or reduce the timeout', 504)
  }
  if (!response.ok) {
    throw new OsmHttpError(`OSM API error: HTTP ${response.status} ${response.statusText}`, response.status)
  }
  let data
  try {
    data = await response.json()
  } catch {
    throw new OsmTransportError('OSM API returned a non-JSON response')
  }
  if (typeof data === 'object' && data !== null && typeof data.error === 'string') {
    throw new OsmHttpError(`OSM API error: ${truncate(data.error, 300)}`, 0)
  }
  return data
}

/** Whether a thrown error justifies trying the fallback geocoder. */
function shouldFallback(error) {
  if (error instanceof OsmTransportError) return true
  if (error instanceof OsmHttpError) return error.status === 429 || error.status >= 500
  return false
}

// ---------------------------------------------------------------------------
// tool builders
// ---------------------------------------------------------------------------

/**
 * Build the four OSM tool definitions.
 * @param config - deployment configuration (see index.js Config).
 * @returns array of ToolDefinition to register on ctx.tools.
 */
export function createOsmTools(config) {
  const userAgent = config.userAgent || DEFAULT_UA
  const nominatimLimiter = createRateLimiter({ minIntervalMs: config.nominatimMinIntervalMs })
  const photonLimiter = createRateLimiter({ minIntervalMs: config.photonMinIntervalMs })
  const overpassLimiter = createRateLimiter({ minIntervalMs: config.overpassMinIntervalMs })
  const osrmLimiter = createRateLimiter({ minIntervalMs: config.osrmMinIntervalMs })
  const { maxMarkers, maxPolylinePoints, maxMetaBytes } = config
  const nominatimBase = config.nominatimBase.replace(/\/+$/, '')
  const photonBase = config.photonBase !== '' ? config.photonBase.replace(/\/+$/, '') : ''
  const overpassUrl = config.overpassBase
  const osrmBase = config.osrmBase.replace(/\/+$/, '')

  // --- geocoding: Nominatim primary, Photon (komoot, also OSM-based) as the
  // transport-failure fallback so a regionally flaky nominatim.openstreetmap.org
  // does not take down geocode/reverse/route-by-name. Disable with photonBase: ''.

  function photonDisplayName(props) {
    return [props.name, props.street, props.city ?? props.state, props.country]
      .filter((v) => typeof v === 'string' && v.trim() !== '')
      .join(', ')
  }

  async function photonSearch(q, { limit = 1, signal } = {}) {
    const url = new URL(`${photonBase}/api/`)
    url.searchParams.set('q', q)
    url.searchParams.set('limit', String(limit))
    url.searchParams.set('lang', 'en')
    await photonLimiter.acquire()
    const data = await fetchJson(url, { signal, timeoutMs: 15_000, userAgent })
    const features = Array.isArray(data?.features) ? data.features : []
    return features.map((f) => {
      const props = f?.properties ?? {}
      const coords = f?.geometry?.coordinates
      const lat = toNum(Array.isArray(coords) ? coords[1] : NaN)
      const lon = toNum(Array.isArray(coords) ? coords[0] : NaN)
      return {
        lat,
        lon,
        display_name: photonDisplayName(props) || String(props.name ?? '?'),
        type: String(props.type ?? 'place'),
        ...props.osm_type !== undefined ? { osm_type: String(props.osm_type) } : {},
        ...Number.isFinite(toNum(props.osm_id)) ? { osm_id: toNum(props.osm_id) } : {},
      }
    }).filter((r) => Number.isFinite(r.lat) && Number.isFinite(r.lon))
  }

  async function photonReverse(lat, lon, signal) {
    const url = new URL(`${photonBase}/api/reverse`)
    url.searchParams.set('lat', String(lat))
    url.searchParams.set('lon', String(lon))
    url.searchParams.set('lang', 'en')
    await photonLimiter.acquire()
    const data = await fetchJson(url, { signal, timeoutMs: 15_000, userAgent })
    const feature = Array.isArray(data?.features) ? data.features[0] : undefined
    const props = feature?.properties ?? {}
    const coords = feature?.geometry?.coordinates
    return {
      lat: toNum(Array.isArray(coords) ? coords[1] : NaN),
      lon: toNum(Array.isArray(coords) ? coords[0] : NaN),
      display_name: photonDisplayName(props) || 'unknown place',
      ...props.osm_type !== undefined ? { osm_type: String(props.osm_type) } : {},
      ...Number.isFinite(toNum(props.osm_id)) ? { osm_id: toNum(props.osm_id) } : {},
      address: props,
    }
  }

  /**
   * Geocode a query string, normalized to [{lat, lon, display_name, type, ...}].
   * Tries Nominatim first, then falls back to Photon on transport/5xx/429.
   */
  async function geocode(q, { limit = 1, signal } = {}) {
    try {
      const url = new URL(`${nominatimBase}/search`)
      url.searchParams.set('format', 'jsonv2')
      url.searchParams.set('q', q)
      url.searchParams.set('limit', String(limit))
      url.searchParams.set('addressdetails', '1')
      url.searchParams.set('accept-language', 'en')
      await nominatimLimiter.acquire()
      const raw = await fetchJson(url, { signal, timeoutMs: 20_000, userAgent })
      return (Array.isArray(raw) ? raw : []).map((item) => ({
        lat: toNum(item.lat),
        lon: toNum(item.lon),
        display_name: String(item.display_name ?? ''),
        type: String(item.type ?? 'place'),
        ...item.osm_type !== undefined ? { osm_type: String(item.osm_type) } : {},
        ...Number.isFinite(toNum(item.osm_id)) ? { osm_id: toNum(item.osm_id) } : {},
      })).filter((r) => Number.isFinite(r.lat) && Number.isFinite(r.lon))
    } catch (error) {
      if (photonBase === '' || !shouldFallback(error)) throw error
      return photonSearch(q, { limit, signal })
    }
  }

  /**
   * Reverse-geocode a coordinate pair, normalized to one object.
   * Same Nominatim → Photon fallback as {@link geocode}.
   */
  async function reverseGeocode(lat, lon, zoom, signal) {
    try {
      const url = new URL(`${nominatimBase}/reverse`)
      url.searchParams.set('format', 'jsonv2')
      url.searchParams.set('lat', String(lat))
      url.searchParams.set('lon', String(lon))
      url.searchParams.set('zoom', String(zoom))
      url.searchParams.set('addressdetails', '1')
      url.searchParams.set('accept-language', 'en')
      await nominatimLimiter.acquire()
      const raw = await fetchJson(url, { signal, timeoutMs: 20_000, userAgent })
      return {
        lat: toNum(raw.lat) || lat,
        lon: toNum(raw.lon) || lon,
        display_name: String(raw.display_name ?? 'unknown place'),
        ...raw.osm_type !== undefined ? { osm_type: String(raw.osm_type) } : {},
        ...Number.isFinite(toNum(raw.osm_id)) ? { osm_id: toNum(raw.osm_id) } : {},
        ...typeof raw.address === 'object' && raw.address !== null ? { address: raw.address } : {},
      }
    } catch (error) {
      if (photonBase === '' || !shouldFallback(error)) throw error
      const photon = await photonReverse(lat, lon, signal)
      return {
        lat: Number.isFinite(photon.lat) ? photon.lat : lat,
        lon: Number.isFinite(photon.lon) ? photon.lon : lon,
        display_name: photon.display_name,
        ...photon.osm_type !== undefined ? { osm_type: photon.osm_type } : {},
        ...photon.osm_id !== undefined ? { osm_id: photon.osm_id } : {},
        address: photon.address,
      }
    }
  }

  const PRESENT_TITLES = {
    geocode: 'OSM · geocode',
    reverse: 'OSM · reverse',
    overpass: 'OSM · overpass',
    route: 'OSM · route',
  }

  const geocodeTool = defineTool({
    name: 'osm_geocode',
    description:
      'Geocode a place name or address with OpenStreetMap Nominatim. Returns up to `limit` matches '
      + 'with coordinates, place type, and (optionally) an address breakdown; the web GUI renders the '
      + 'results on an interactive map. Uses the public Nominatim instance (max 1 request/second).',
    parameters: {
      q: {
        type: 'string',
        required: true,
        description: 'Free-form place name, address, or query, e.g. "Red Square, Moscow" or "Eiffel Tower".',
      },
      limit: {
        type: 'integer',
        description: 'Maximum number of matches to return (1–20, default 10).',
      },
      countrycodes: {
        type: 'string',
        description: 'Optional comma-separated ISO 3166-1 alpha-2 codes to restrict the search, e.g. "ru,de".',
      },
      viewbox: {
        type: 'string',
        description: 'Optional bounding box to bias the search: "lon1,lat1,lon2,lat2" (west, south, east, north).',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          query: { type: 'string', required: true },
          results: {
            type: 'array',
            required: true,
            items: {
              type: 'object',
              additionalProperties: false,
              properties: {
                name: { type: 'string', required: true },
                displayName: { type: 'string', required: true },
                lat: { type: 'number', required: true },
                lon: { type: 'number', required: true },
                type: { type: 'string', required: true },
                osmType: { type: 'string' },
                osmId: { type: 'integer' },
              },
            },
          },
        },
      },
      render: (_args, value) => {
        if (value.results.length === 0) return [{ type: 'text', text: `No matches for "${value.query}".` }]
        const lines = value.results.map((r, i) =>
          `${i + 1}. ${r.name} — ${truncate(r.displayName, 110)} — ${r.lat.toFixed(5)}, ${r.lon.toFixed(5)} (${r.type})`,
        )
        return [{ type: 'text', text: [`Geocode "${value.query}": ${value.results.length} result(s).`, ...lines].join('\n') }]
      },
      presentationMeta: (_args, value) => {
        const markers = value.results.slice(0, maxMarkers).map((r) => ({
          lat: r.lat,
          lon: r.lon,
          title: r.name,
          subtitle: truncate(r.displayName, 160),
        }))
        const coords = markers.map((m) => [m.lat, m.lon])
        return capMeta({
          kind: 'osm-map',
          tool: 'geocode',
          label: `Geocode: "${truncate(value.query, 60)}" — ${value.results.length} result(s)`,
          markers,
          bounds: boundsOf(coords),
        }, maxMetaBytes)
      },
    },
    isConcurrencySafe: () => true,
    timeoutMs: 25_000,
    async execute(args, exec) {
      const q = String(args.q).trim()
      if (q === '') throw new Error('osm_geocode: q must not be empty')
      const limit = Math.max(1, Math.min(20, args.limit ?? 10))
      const hits = await geocode(q, { limit, signal: exec.signal })
      const results = hits.map((item) => ({
        name: truncate(String(item.display_name ?? '?').split(',')[0], 80),
        displayName: String(item.display_name ?? ''),
        lat: item.lat,
        lon: item.lon,
        type: String(item.type ?? 'place'),
        ...item.osm_type !== undefined ? { osmType: String(item.osm_type) } : {},
        ...Number.isFinite(toNum(item.osm_id)) ? { osmId: toNum(item.osm_id) } : {},
      }))
      return { query: q, results }
    },
    presentCall: () => ({ card: 'generic', title: PRESENT_TITLES.geocode, kind: 'other' }),
    presentResult(_args, result) {
      if (result.isError) return undefined
      const meta = osmMetaFrom(result.meta)
      if (meta === undefined) return undefined
      return { card: 'generic', title: `OSM geocode · ${truncate(meta.label, 60)}` }
    },
  })

  const reverseTool = defineTool({
    name: 'osm_reverse',
    description:
      'Reverse-geocode a coordinate pair with OpenStreetMap Nominatim: return the closest address and '
      + 'place details. The web GUI drops a marker on the map.',
    parameters: {
      lat: { type: 'number', required: true, description: 'Latitude (WGS84), e.g. 55.7539.' },
      lon: { type: 'number', required: true, description: 'Longitude (WGS84), e.g. 37.6208.' },
      zoom: {
        type: 'integer',
        description: 'Address detail level 0–18 (default 18 = building-level detail; lower = coarser region).',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          lat: { type: 'number', required: true },
          lon: { type: 'number', required: true },
          displayName: { type: 'string', required: true },
          osmType: { type: 'string' },
          osmId: { type: 'integer' },
          address: { type: 'object', additionalProperties: true },
        },
      },
      render: (_args, value) => {
        const addressLine = value.address !== undefined && Object.keys(value.address).length > 0
          ? `\naddress: ${JSON.stringify(value.address)}`
          : ''
        const osmRef = value.osmType !== undefined ? `\nosm: ${value.osmType}/${value.osmId}` : ''
        return [{ type: 'text', text: `Reverse geocode ${value.lat.toFixed(5)}, ${value.lon.toFixed(5)}:\n${value.displayName}${addressLine}${osmRef}` }]
      },
      presentationMeta: (_args, value) => capMeta({
        kind: 'osm-map',
        tool: 'reverse',
        label: `Reverse: ${truncate(value.displayName, 80)}`,
        center: [value.lat, value.lon],
        markers: [{ lat: value.lat, lon: value.lon, title: truncate(value.displayName, 160) }],
      }, maxMetaBytes),
    },
    isConcurrencySafe: () => true,
    timeoutMs: 25_000,
    async execute(args, exec) {
      const lat = Number(args.lat)
      const lon = Number(args.lon)
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new Error('osm_reverse: lat/lon must be numbers')
      const zoom = Math.max(0, Math.min(18, args.zoom ?? 18))
      const raw = await reverseGeocode(lat, lon, zoom, exec.signal)
      const value = {
        lat: toNum(raw.lat) || lat,
        lon: toNum(raw.lon) || lon,
        displayName: String(raw.display_name ?? 'unknown place'),
        ...raw.osm_type !== undefined ? { osmType: String(raw.osm_type) } : {},
        ...Number.isFinite(toNum(raw.osm_id)) ? { osmId: toNum(raw.osm_id) } : {},
        ...typeof raw.address === 'object' && raw.address !== null ? { address: raw.address } : {},
      }
      return value
    },
    presentCall: () => ({ card: 'generic', title: PRESENT_TITLES.reverse, kind: 'other' }),
    presentResult(_args, result) {
      if (result.isError) return undefined
      const meta = osmMetaFrom(result.meta)
      if (meta === undefined) return undefined
      return { card: 'generic', title: `OSM reverse · ${truncate(meta.label, 60)}` }
    },
  })

  const overpassTool = defineTool({
    name: 'osm_overpass',
    description:
      'Run an Overpass QL query against the public OpenStreetMap Overpass API: extract POIs, features, '
      + 'or data around coordinates. The web GUI renders matching nodes as markers and (simple) ways as '
      + 'lines. Example query: `node["amenity"="cafe"](around:1000,55.7558,37.6173); out;` — you may '
      + 'omit the `[out:json][timeout:N]` header, the tool adds it. Keep queries bounded '
      + '([timeout:25] default) — the public endpoint is shared.',
    parameters: {
      query: {
        type: 'string',
        required: true,
        description: 'Overpass QL body, e.g. node["amenity"="cafe"](around:1000,55.7558,37.6173); out;',
      },
      timeout: {
        type: 'integer',
        description: 'Overpass timeout in seconds (5–180, default 25).',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          query: { type: 'string', required: true },
          count: { type: 'integer', required: true },
          nodes: { type: 'integer' },
          ways: { type: 'integer' },
          relations: { type: 'integer' },
          sample: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              properties: {
                title: { type: 'string', required: true },
                kind: { type: 'string', required: true },
                lat: { type: 'number' },
                lon: { type: 'number' },
                points: {
                  type: 'array',
                  items: { type: 'array', items: { type: 'number' } },
                },
              },
            },
          },
        },
      },
      render: (_args, value) => {
        const head = `Overpass "${truncate(value.query, 90)}": ${value.count} element(s)`
        if (value.sample.length === 0) return [{ type: 'text', text: `${head} — no geometry to show.` }]
        const lines = value.sample.slice(0, 10).map((s) => {
          const pos = Number.isFinite(s.lat) ? ` — ${s.lat.toFixed(5)}, ${s.lon.toFixed(5)}` : ''
          return `- ${s.title} (${s.kind})${pos}`
        })
        return [{ type: 'text', text: [head, ...lines, value.sample.length > 10 ? `… and ${value.sample.length - 10} more` : ''].filter(Boolean).join('\n') }]
      },
      presentationMeta: (_args, value) => {
        const markers = []
        const polylines = []
        for (const s of value.sample) {
          if (Number.isFinite(s.lat) && Number.isFinite(s.lon)) {
            markers.push({ lat: s.lat, lon: s.lon, title: s.title, subtitle: s.kind })
          } else if (Array.isArray(s.points) && s.points.length >= 2 && polylines.length < 3) {
            polylines.push(decimate(s.points, maxPolylinePoints))
          }
          if (markers.length >= maxMarkers) break
        }
        const all = [...markers.map((m) => [m.lat, m.lon]), ...polylines.flat()]
        return capMeta({
          kind: 'osm-map',
          tool: 'overpass',
          label: `Overpass: ${value.count} element(s)`,
          markers,
          ...polylines.length > 0 ? { polylines } : {},
          bounds: boundsOf(all),
        }, maxMetaBytes)
      },
    },
    isConcurrencySafe: () => true,
    timeoutMs: 75_000,
    async execute(args, exec) {
      let query = String(args.query).trim()
      if (query === '') throw new Error('osm_overpass: query must not be empty')
      const timeout = Math.max(5, Math.min(180, args.timeout ?? 25))
      if (!/^\[out:/u.test(query)) {
        query = `[out:json][timeout:${timeout}];\n${query}`
      }
      await overpassLimiter.acquire()
      const data = await fetchJson(overpassUrl, {
        signal: exec.signal,
        timeoutMs: Math.min(70_000, timeout * 1000 + 10_000),
        userAgent,
        method: 'POST',
        form: true,
        body: new URLSearchParams({ data: query }).toString(),
      })
      const elements = Array.isArray(data?.elements) ? data.elements : []
      const sample = []
      let nodes = 0
      let ways = 0
      let relations = 0
      for (const el of elements) {
        if (el === null || typeof el !== 'object') continue
        const type = String(el.type ?? 'node')
        if (type === 'node') nodes += 1
        else if (type === 'way') ways += 1
        else relations += 1
        const tags = typeof el.tags === 'object' && el.tags !== null ? el.tags : {}
        const name = String(tags.name ?? tags['name:en'] ?? '')
        const tagKey = TAG_PRIORITY.find((k) => tags[k] !== undefined)
        const kind = tagKey !== undefined ? `${tagKey}=${tags[tagKey]}` : type
        const title = name !== '' ? name : kind === type ? `${type} #${el.id}` : `${kind} #${el.id}`
        const lat = toNum(el.lat)
        const lon = toNum(el.lon)
        if (Number.isFinite(lat) && Number.isFinite(lon)) {
          sample.push({ title, kind, lat, lon })
          continue
        }
        if (Array.isArray(el.geometry) && el.geometry.length >= 2) {
          const points = []
          for (const p of el.geometry) {
            const pl = toNum(p?.lat)
            const pn = toNum(p?.lon)
            if (Number.isFinite(pl) && Number.isFinite(pn)) points.push([pl, pn])
          }
          if (points.length >= 2) sample.push({ title, kind, points })
          continue
        }
        if (typeof el.center === 'object' && el.center !== null) {
          const cl = toNum(el.center.lat)
          const cn = toNum(el.center.lon)
          if (Number.isFinite(cl) && Number.isFinite(cn)) sample.push({ title, kind, lat: cl, lon: cn })
        }
      }
      return { query, count: elements.length, nodes, ways, relations, sample }
    },
    presentCall: () => ({ card: 'generic', title: PRESENT_TITLES.overpass, kind: 'other' }),
    presentResult(_args, result) {
      if (result.isError) return undefined
      const meta = osmMetaFrom(result.meta)
      if (meta === undefined) return undefined
      return { card: 'generic', title: `OSM overpass · ${truncate(meta.label, 60)}` }
    },
  })

  const routeTool = defineTool({
    name: 'osm_route',
    description:
      'Compute a route between two points with OSRM (driving / walking / cycling) and render it on the '
      + 'map in the web GUI. Endpoints may be place names (geocoded via Nominatim) or "lat, lon" '
      + 'coordinates. Returns distance, duration, and the simplified geometry.',
    parameters: {
      from: {
        type: 'string',
        required: true,
        description: 'Start point: a place name/address, or "lat, lon" coordinates.',
      },
      to: {
        type: 'string',
        required: true,
        description: 'End point: a place name/address, or "lat, lon" coordinates.',
      },
      profile: {
        type: 'string',
        enum: ['driving', 'walking', 'cycling'],
        description: 'Routing profile (default driving).',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          from: { type: 'string', required: true },
          to: { type: 'string', required: true },
          profile: { type: 'string', required: true },
          distanceMeters: { type: 'number', required: true },
          durationSeconds: { type: 'number', required: true },
          start: {
            type: 'object',
            additionalProperties: false,
            properties: { lat: { type: 'number', required: true }, lon: { type: 'number', required: true } },
          },
          end: {
            type: 'object',
            additionalProperties: false,
            properties: { lat: { type: 'number', required: true }, lon: { type: 'number', required: true } },
          },
        },
      },
      render: (_args, value) => [
        {
          type: 'text',
          text: [
            `Route ${value.profile}: ${humanDistance(value.distanceMeters)} · ${humanDuration(value.durationSeconds)}`,
            `from: ${value.from}`,
            `to: ${value.to}`,
            `start: ${value.start.lat.toFixed(5)}, ${value.start.lon.toFixed(5)}`,
            `end: ${value.end.lat.toFixed(5)}, ${value.end.lon.toFixed(5)}`,
          ].join('\n'),
        },
      ],
      presentationMeta: (_args, value) => capMeta({
        kind: 'osm-map',
        tool: 'route',
        label: `Route: ${truncate(value.from, 28)} → ${truncate(value.to, 28)} · ${humanDistance(value.distanceMeters)} · ${humanDuration(value.durationSeconds)}`,
        polyline: decimate(value.geometry, maxPolylinePoints),
        markers: [
          { lat: value.start.lat, lon: value.start.lon, title: truncate(value.from, 80), color: 'green' },
          { lat: value.end.lat, lon: value.end.lon, title: truncate(value.to, 80), color: 'red' },
        ],
      }, maxMetaBytes),
    },
    isConcurrencySafe: () => true,
    timeoutMs: 60_000,
    async execute(args, exec) {
      const from = String(args.from).trim()
      const to = String(args.to).trim()
      if (from === '' || to === '') throw new Error('osm_route: from and to are required')
      const profile = args.profile ?? 'driving'
      const fromCoords = parseCoords(from)
      const toCoords = parseCoords(to)

      const [startLat, startLon] = fromCoords ?? await resolveEndpoint(from, exec.signal)
      const [endLat, endLon] = toCoords ?? await resolveEndpoint(to, exec.signal)

      const url = new URL(`${osrmBase}/route/v1/${profile}/${startLon},${startLat};${endLon},${endLat}`)
      url.searchParams.set('overview', 'simplified')
      url.searchParams.set('geometries', 'geojson')
      url.searchParams.set('alternatives', 'false')
      url.searchParams.set('steps', 'false')
      await osrmLimiter.acquire()
      const data = await fetchJson(url, { signal: exec.signal, timeoutMs: 30_000, userAgent })
      if (data.code !== 'Ok' || !Array.isArray(data.routes) || data.routes.length === 0) {
        throw new Error(`OSRM could not compute a route (${data.code ?? 'unknown error'}) — endpoints may be unreachable for ${profile}`)
      }
      const best = data.routes[0]
      const geometry = []
      const coords = best.geometry?.coordinates
      if (Array.isArray(coords)) {
        for (const [lon, lat] of coords) {
          const l = toNum(lat)
          const n = toNum(lon)
          if (Number.isFinite(l) && Number.isFinite(n)) geometry.push([l, n])
        }
      }
      return {
        from,
        to,
        profile,
        distanceMeters: Number(best.distance) || 0,
        durationSeconds: Number(best.duration) || 0,
        start: { lat: startLat, lon: startLon },
        end: { lat: endLat, lon: endLon },
        geometry,
      }
    },
    presentCall: () => ({ card: 'generic', title: PRESENT_TITLES.route, kind: 'other' }),
    presentResult(_args, result) {
      if (result.isError) return undefined
      const meta = osmMetaFrom(result.meta)
      if (meta === undefined) return undefined
      return { card: 'generic', title: `OSM route · ${truncate(meta.label, 60)}` }
    },
  })

  /** Geocode one endpoint name for the route tool. */
  async function resolveEndpoint(name, signal) {
    const hits = await geocode(name, { limit: 1, signal })
    const hit = hits[0]
    if (hit === undefined || !Number.isFinite(hit.lat) || !Number.isFinite(hit.lon)) {
      throw new Error(`osm_route: could not geocode "${truncate(name, 60)}" — give a more precise name or "lat, lon" coordinates`)
    }
    return [hit.lat, hit.lon]
  }

  return [geocodeTool, reverseTool, overpassTool, routeTool]
}
