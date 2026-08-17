/**
 * dsh-osm, browser half.
 *
 * Renders the `presentationMeta` map descriptor that the osm_* tools attach
 * to their results as an interactive Leaflet card in the conversation
 * (`tool.call.toolview`, keyed per tool name). Replay-stable: everything
 * drawn derives from the logged call slice (markers / polylines / bounds in
 * the meta), never from a live API — the only network the browser does is
 * OSM map tiles and the plugin's own vendored Leaflet assets served by the
 * host at /osm/leaflet/ (no CDN).
 *
 * The default Leaflet marker icons resolve against /osm/leaflet/images/
 * because Leaflet auto-detects its imagePath from the script URL, so the
 * vendored icons just work. Circle markers are used anyway for colorable
 * points; the default icon is used for route start/end pins.
 */

window.__ModuleLoader__.load({
  id: "dsh-osm",
  factory: (require) => {
    const React = require("react");
    const { useEffect, useRef, useState } = React;

    const inject = ["slots"];

    const TOOL_KEYS = ["osm_geocode", "osm_reverse", "osm_overpass", "osm_route"];

    const TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    const TILE_ATTRIBUTION =
      '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors';
    const MAP_HEIGHT = 420;

    const COLORS = {
      green: "#2e9e6b",
      red: "#d34f4f",
      blue: "#367bbf",
    };

    // ---------------------------------------------------------------------
    // wire narrowing — the persisted meta is untrusted, never assume shape
    // ---------------------------------------------------------------------

    function toNum(value) {
      const n = typeof value === "string" ? Number(value) : value;
      return Number.isFinite(n) ? n : NaN;
    }

    function narrowMeta(meta) {
      if (typeof meta !== "object" || meta === null) return undefined;
      if (meta.kind !== "osm-map") return undefined;
      if (typeof meta.tool !== "string" || typeof meta.label !== "string") return undefined;
      const out = { kind: "osm-map", tool: meta.tool, label: meta.label };
      if (typeof meta.center === "object" && meta.center !== null) {
        const lat = toNum(meta.center[0]);
        const lon = toNum(meta.center[1]);
        if (Number.isFinite(lat) && Number.isFinite(lon)) out.center = [lat, lon];
      }
      if (Array.isArray(meta.markers)) {
        const markers = [];
        for (const m of meta.markers) {
          if (typeof m !== "object" || m === null) continue;
          const lat = toNum(m.lat);
          const lon = toNum(m.lon);
          if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
          markers.push({
            lat,
            lon,
            title: typeof m.title === "string" ? m.title : "",
            ...(typeof m.subtitle === "string" ? { subtitle: m.subtitle } : {}),
            ...(typeof m.color === "string" ? { color: m.color } : {}),
          });
        }
        if (markers.length > 0) out.markers = markers;
      }
      if (Array.isArray(meta.polyline)) {
        const points = [];
        for (const p of meta.polyline) {
          if (typeof p !== "object" || p === null) continue;
          const lat = toNum(p[0]);
          const lon = toNum(p[1]);
          if (Number.isFinite(lat) && Number.isFinite(lon)) points.push([lat, lon]);
        }
        if (points.length > 0) out.polyline = points;
      }
      if (Array.isArray(meta.polylines)) {
        const polylines = [];
        for (const line of meta.polylines) {
          if (!Array.isArray(line)) continue;
          const points = [];
          for (const p of line) {
            if (typeof p !== "object" || p === null) continue;
            const lat = toNum(p[0]);
            const lon = toNum(p[1]);
            if (Number.isFinite(lat) && Number.isFinite(lon)) points.push([lat, lon]);
          }
          if (points.length >= 2) polylines.push(points);
        }
        if (polylines.length > 0) out.polylines = polylines;
      }
      if (typeof meta.bounds === "object" && meta.bounds !== null) {
        const sw = meta.bounds[0];
        const ne = meta.bounds[1];
        if (Array.isArray(sw) && Array.isArray(ne)) {
          const swLat = toNum(sw[0]);
          const swLon = toNum(sw[1]);
          const neLat = toNum(ne[0]);
          const neLon = toNum(ne[1]);
          if (
            Number.isFinite(swLat) && Number.isFinite(swLon) &&
            Number.isFinite(neLat) && Number.isFinite(neLon)
          ) {
            out.bounds = [[swLat, swLon], [neLat, neLon]];
          }
        }
      }
      return out;
    }

    function firstResultLine(block) {
      const content = block && block.content;
      if (Array.isArray(content)) {
        for (const part of content) {
          if (part && part.type === "text" && typeof part.text === "string" && part.text.length > 0) {
            const newline = part.text.indexOf("\n");
            return newline === -1 ? part.text : part.text.slice(0, newline);
          }
        }
      }
      return "OSM result";
    }

    // ---------------------------------------------------------------------
    // leaflet bootstrap — vendored assets served by the plugin host
    // ---------------------------------------------------------------------

    let leafletPromise = null;

    function ensureLeaflet() {
      if (typeof document === "undefined") return Promise.reject(new Error("no document"));
      if (!leafletPromise) {
        leafletPromise = new Promise((resolve, reject) => {
          const css = document.createElement("link");
          css.rel = "stylesheet";
          css.href = "/osm/leaflet/leaflet.css";
          document.head.appendChild(css);
          if (window.L && window.L.map) {
            resolve();
            return;
          }
          const script = document.createElement("script");
          script.src = "/osm/leaflet/leaflet.js";
          script.onload = () => (window.L && window.L.map ? resolve() : reject(new Error("leaflet loaded without L.map")));
          script.onerror = () => reject(new Error("failed to load /osm/leaflet/leaflet.js"));
          document.head.appendChild(script);
        });
      }
      return leafletPromise;
    }

    // ---------------------------------------------------------------------
    // drawing
    // ---------------------------------------------------------------------

    function popupHtml(marker) {
      const parts = [];
      if (marker.title) parts.push(`<strong>${escapeHtml(marker.title)}</strong>`);
      if (marker.subtitle) parts.push(`<span style="opacity:.75">${escapeHtml(marker.subtitle)}</span>`);
      return parts.join("<br>");
    }

    function escapeHtml(value) {
      return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
    }

    function drawMap(L, map, meta) {
      const latlngs = [];

      // Route geometry first so it sits under the markers.
      if (meta.polyline && meta.polyline.length >= 2) {
        L.polyline(meta.polyline, {
          color: "#367bbf",
          weight: 4,
          opacity: 0.85,
        }).addTo(map);
        latlngs.push(...meta.polyline);
      }
      if (Array.isArray(meta.polylines)) {
        for (const line of meta.polylines) {
          if (line.length >= 2) {
            L.polyline(line, {
              color: "#367bbf",
              weight: 3,
              opacity: 0.7,
              dashArray: "6 6",
            }).addTo(map);
            latlngs.push(...line);
          }
        }
      }

      if (Array.isArray(meta.markers)) {
        for (const m of meta.markers) {
          const color = COLORS[m.color] || COLORS.blue;
          const marker = L.circleMarker([m.lat, m.lon], {
            radius: 7,
            color,
            weight: 2,
            fillColor: color,
            fillOpacity: 0.85,
          }).addTo(map);
          const html = popupHtml(m);
          if (html !== "") marker.bindPopup(html, { maxWidth: 320 });
          latlngs.push([m.lat, m.lon]);
        }
      }

      if (meta.center && latlngs.length === 0) latlngs.push(meta.center);

      if (meta.bounds) {
        map.fitBounds(L.latLngBounds(meta.bounds), { padding: [28, 28] });
      } else if (latlngs.length === 1) {
        map.setView(latlngs[0], 15);
      } else if (latlngs.length > 1) {
        map.fitBounds(L.latLngBounds(latlngs), { padding: [28, 28] });
      } else {
        map.setView([0, 0], 2);
      }
    }

    // ---------------------------------------------------------------------
    // the card
    // ---------------------------------------------------------------------

    const headerStyle = {
      display: "flex",
      alignItems: "baseline",
      gap: 8,
      fontSize: 12,
      opacity: 0.65,
      margin: "2px 0 6px",
      overflow: "hidden",
      whiteSpace: "nowrap",
    };

    const mapWrapStyle = {
      position: "relative",
      height: MAP_HEIGHT,
      borderRadius: 8,
      overflow: "hidden",
      border: "1px solid var(--dsw-alias-border-l1, rgba(128,128,128,.35))",
    };

    function MapFrame({ meta }) {
      const containerRef = useRef(null);
      const [failed, setFailed] = useState(false);

      useEffect(() => {
        let map = null;
        let disposed = false;
        ensureLeaflet()
          .then(() => {
            if (disposed) return;
            const el = containerRef.current;
            if (!el || !window.L || !window.L.map) return;
            map = window.L.map(el, { zoomControl: true, attributionControl: true });
            window.L.tileLayer(TILE_URL, {
              maxZoom: 19,
              attribution: TILE_ATTRIBUTION,
            }).addTo(map);
            try {
              drawMap(window.L, map, meta);
            } catch (error) {
              // Never let a drawing bug take the card down; keep the tiles.
              setFailed(true);
            }
            // The container may have been sized after mount (layout shift);
            // ask Leaflet to re-measure once.
            setTimeout(() => { if (map) map.invalidateSize(); }, 0);
          })
          .catch(() => setFailed(true));
        return () => {
          disposed = true;
          if (map) {
            map.remove();
            map = null;
          }
        };
      }, [meta]);

      return React.createElement("div", { style: mapWrapStyle },
        failed
          ? React.createElement("div", { style: { padding: 12, fontSize: 12, opacity: 0.7 } },
              "Map failed to load — see the text result above.")
          : null,
        React.createElement("div", { ref: containerRef, style: { position: "absolute", inset: 0 } }),
      );
    }

    /**
     * Keyed toolview for the osm_* tools. Running calls and malformed or
     * failed results stay quiet single lines; only a well-formed persisted
     * meta mounts the map.
     */
    function OsmMapCard({ block }) {
      if (!("kind" in block)) {
        return React.createElement("div", { style: headerStyle }, "OSM · rendering…");
      }
      if (block.isError) {
        return React.createElement("div", { style: headerStyle }, "OSM · " + firstResultLine(block));
      }
      const meta = narrowMeta(block.meta);
      if (meta === undefined) {
        return React.createElement("div", { style: headerStyle }, firstResultLine(block));
      }
      return React.createElement("div", null,
        React.createElement("div", { style: headerStyle, title: meta.label },
          React.createElement("span", { style: { fontWeight: 500 } }, "OSM · " + meta.label),
        ),
        React.createElement(MapFrame, { meta }),
      );
    }

    // ---------------------------------------------------------------------
    // registration
    // ---------------------------------------------------------------------

    function apply(ctx) {
      for (const key of TOOL_KEYS) {
        ctx.slots.inject("tool.call.toolview", () =>
          ctx.slots.register(
            { name: "tool.call.toolview", key },
            OsmMapCard,
          ),
        );
      }
    }

    return { apply, inject };
  },
});
