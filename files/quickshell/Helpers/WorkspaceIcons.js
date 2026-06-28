.pragma library

const manifestUrl = Qt.resolvedUrl("../Bar/Icons/workspaces/manifest.json");
const iconBaseUrl = Qt.resolvedUrl("../Bar/Icons/");

let manifestCache = null;
let slugIndex = {};
let hyprIndex = {};
let idIndex = {};

function slugify(value) {
    try {
        var lower = String(value || "").toLowerCase();
        lower = lower.replace(/[^a-z0-9]+/g, "-");
        lower = lower.replace(/^-+/, "").replace(/-+$/, "");
        return lower;
    } catch (e) {
        console.warn("[WorkspaceIcons.slugify]", e);
        return "";
    }
}

function buildIndexes() {
    slugIndex = {};
    hyprIndex = {};
    idIndex = {};
    if (!manifestCache || !manifestCache.icons) return;
    for (var i = 0; i < manifestCache.icons.length; i++) {
        var entry = manifestCache.icons[i] || {};
        if (entry.slug) slugIndex[entry.slug] = entry;
        if (entry.hyprName) hyprIndex[entry.hyprName] = entry;
        if (typeof entry.id === "number") idIndex[entry.id] = entry;
    }
}

function loadManifest() {
    if (manifestCache) return manifestCache;
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", manifestUrl, false);
        xhr.send();
        if (xhr.status !== 0 && xhr.status !== 200)
            throw new Error("manifest fetch failed: status " + xhr.status);
        manifestCache = JSON.parse(xhr.responseText || "{}");
        buildIndexes();
        return manifestCache;
    } catch (e) {
        console.warn("WorkspaceIcons: unable to load manifest", e);
        manifestCache = null;
        slugIndex = {};
        hyprIndex = {};
        idIndex = {};
        return null;
    }
}

function entryForName(name, fallbackId) {
    var data = loadManifest();
    if (!data) return null;
    var normalized = (name || "").trim();
    if (normalized && hyprIndex[normalized]) return hyprIndex[normalized];
    if (normalized) {
        var colonIdx = normalized.indexOf(":");
        var slugSource = colonIdx >= 0 ? normalized.slice(colonIdx + 1) : normalized;
        var slug = slugify(slugSource);
        if (slug && slugIndex[slug]) return slugIndex[slug];
    }
    if (typeof fallbackId === "number" && idIndex[fallbackId]) return idIndex[fallbackId];
    return null;
}

function entryForWorkspace(name, id) {
    return entryForName(name, id);
}

function manifestViewBox() {
    var data = loadManifest();
    if (!data || data.viewBox === undefined) return 1024;
    var v = Number(data.viewBox);
    return isFinite(v) && v > 0 ? v : 1024;
}

