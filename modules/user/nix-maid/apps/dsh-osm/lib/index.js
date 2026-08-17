/**
 * dsh-osm, host half.
 *
 * Registers the four osm_* tools on `ctx.tools`, a bundled `osm` skill on
 * `ctx.skills` (the API-etiquette contract the model should read before its
 * first call), and serves the vendored Leaflet assets to the browser at
 * /osm/leaflet/ so the client card needs no CDN.
 *
 * The browser half (`lib/client.js`) renders the `presentationMeta` map
 * descriptor; a client without it degrades to the tools' text results, so
 * TUI and headless surfaces keep working unchanged.
 *
 * @module dsh-osm
 */

import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { extname } from 'node:path'
import z from '@deepseek-ai/schemastery'
import { BUNDLED_SKILL_RANK } from '@deepseek-ai/dsh-skill'
import { createOsmTools, osmMetaFrom } from './tools.js'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-osm'

/** Required services: tool registry, skill registry, and the web server. */
export const inject = ['tools', 'skills', 'webServer']

/** Deployment configuration, validated by the Loader. */
export const Config = z.object({
  nominatimBase: z.string().default('https://nominatim.openstreetmap.org'),
  // Photon (komoot, OSM-based) is the fallback geocoder for transport
  // failures / 429 / 5xx on Nominatim; set to '' to disable the fallback.
  photonBase: z.string().default('https://photon.komoot.io'),
  overpassBase: z.string().default('https://overpass-api.de/api/interpreter'),
  osrmBase: z.string().default('https://router.project-osrm.org'),
  userAgent: z.string().default('dsh-osm/0.1 (DeepSeek Harness OSM plugin; interactive light use)'),
  nominatimMinIntervalMs: z.natural().default(1100),
  photonMinIntervalMs: z.natural().default(500),
  overpassMinIntervalMs: z.natural().default(1100),
  osrmMinIntervalMs: z.natural().default(600),
  maxMarkers: z.natural().default(50),
  maxPolylinePoints: z.natural().default(800),
  maxMetaBytes: z.natural().default(120_000),
})

// ---------------------------------------------------------------------------
// bundled skill
// ---------------------------------------------------------------------------

const SKILL_NAME = 'osm'
const SKILL_DESCRIPTION =
  'OpenStreetMap integration: geocoding, reverse geocoding, POI/data queries (Overpass), and routing '
  + 'via the osm_* tools, with the web GUI map card. Load before the first osm_* call — it covers '
  + 'which tool fits which task, coordinate conventions, and the public-API etiquette the tools '
  + 'enforce (rate limits, timeouts).'

const LEAFLET_ROOT = new URL('../assets/leaflet/', import.meta.url)
const SKILL_BODY = new URL('../assets/osm-skill.md', import.meta.url)

const CANDIDATE = {
  name: SKILL_NAME,
  description: SKILL_DESCRIPTION,
  invocation: { modelInvocable: true, userInvocable: true },
  provider: 'dsh-osm',
  source: 'bundled',
  resourceBase: {
    kind: 'directory',
    path: fileURLToPath(new URL('../assets/', import.meta.url)),
  },
  rank: BUNDLED_SKILL_RANK,
  locator: SKILL_BODY,
}

/** The bundled `osm` skill provider (mirrors the dsh-skill-badge shape). */
export const osmSkillProvider = {
  name: 'dsh-osm',
  list: () => Promise.resolve([CANDIDATE]),
  async get(candidate) {
    return {
      name: candidate.name,
      description: candidate.description,
      invocation: candidate.invocation,
      provider: candidate.provider,
      source: candidate.source,
      resourceBase: candidate.resourceBase,
      content: await readFile(candidate.locator, 'utf8'),
    }
  },
}

// ---------------------------------------------------------------------------
// leaflet asset serving (no CDN: the app serves its own copy)
// ---------------------------------------------------------------------------

const CONTENT_TYPES = {
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
}

const ALLOWED_LEAFLET = new Set([
  'leaflet.js',
  'leaflet.css',
  'images/layers.png',
  'images/layers-2x.png',
  'images/marker-icon.png',
  'images/marker-icon-2x.png',
  'images/marker-shadow.png',
])

/** Prefix route handler: /osm/leaflet/<file> → the vendored asset. */
function leafletHandler(req, res) {
  // Prefix handlers receive only (req, res); resolve the requested file from
  // the request URL ourselves.
  const pathname = new URL(req.url ?? '/', 'http://x').pathname
  const relative = pathname.slice('/osm/leaflet/'.length)
  if (!ALLOWED_LEAFLET.has(relative)) {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
    res.end('not found')
    return
  }
  readFile(new URL(relative, LEAFLET_ROOT))
    .then((body) => {
      res.writeHead(200, {
        'content-type': CONTENT_TYPES[extname(relative)] ?? 'application/octet-stream',
        'content-length': body.length,
        'cache-control': 'public, max-age=3600',
      })
      res.end(body)
    })
    .catch((error) => {
      res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' })
      res.end(String(error))
    })
}

// ---------------------------------------------------------------------------
// plugin entry
// ---------------------------------------------------------------------------

/**
 * Register the tools, the skill, and the Leaflet asset route.
 * @param ctx - registrant context.
 * @param config - validated deployment configuration.
 */
export function apply(ctx, config) {
  for (const tool of createOsmTools(config)) {
    ctx.tools.register(tool)
  }
  ctx.skills.registerProvider(() => osmSkillProvider)
  ctx.effect(() => ctx.webServer.register({
    kind: 'prefix',
    path: '/osm/leaflet/',
    handler: leafletHandler,
  }), 'dsh-osm.leaflet')
}

export { osmMetaFrom }
