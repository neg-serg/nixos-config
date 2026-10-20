-- cover.luau — the logic of the album-art resolver (see cover.plm).
--
-- Legacy: files/quickshell/Services/CoverResolver.qml. The MPRIS art URL is the
-- starting point, not the answer: players export a temporary file, while the
-- album directory holds the real cover. The QS resolver ranks the sisters
--
--   cover · front · folder · album   (that order), then any other image
--
-- by name, over the extensions jpg/jpeg/png/gif/webp, and publishes the best
-- file. This port does the same by listing the directory with `ls -1` (a
-- plugin's files service cannot leave its own folder), debounced by the QS
-- `media.art.debounce` (60 ms) so a burst of metadata changes is one listing.
--
-- The result is a plain path: pleamar's `image … = from` paints an icon name or
-- a path that starts with `/`, so a remote http(s) art URL is reported as "not
-- found" rather than handed over broken.
--
-- Permissions are the plugin's own: ls; media (the art URL and the track).

local DEBOUNCE_MS = 60
local CANONICAL = { "cover", "front", "folder", "album" }
local IMAGES = { jpg = true, jpeg = true, png = true, gif = true, webp = true }

local lastKey = nil
local timer = nil

local function decodePercent(text)
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function pathOf(url)
    if type(url) ~= "string" then return nil end
    if url:sub(1, 7) == "file://" then
        return decodePercent(url:sub(8))
    end
    if url:sub(1, 1) == "/" then return url end
    return nil
end

local function dirOf(path)
    return path:match("^(.*)/[^/]+$")
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function stem(name)
    local base = name:match("^(.*)%.[^.]*$") or name
    return base:lower()
end

local function extension(name)
    return (name:match("%.([^.]*)$") or ""):lower()
end

local function rankOf(name)
    for index, canonical in ipairs(CANONICAL) do
        if stem(name) == canonical then return index end
    end
    return #CANONICAL + 1
end

local function publish(path, found, raw)
    text.cover = path or ""
    text.raw = raw or ""
    fact.found = found == true
end

local function choose(candidates, dir, raw)
    local best, bestRank = nil, nil
    for _, name in ipairs(candidates) do
        if IMAGES[extension(name)] then
            local rank = rankOf(name)
            if not best or rank < bestRank or (rank == bestRank and name < best) then
                best, bestRank = name, rank
            end
        end
    end
    if best then
        publish(dir .. "/" .. best, true, raw)
        return
    end
    -- No sister file: the art URL itself is the only picture there is. It is
    -- already a file in the album's directory (or a player's export).
    publish(pathOf(raw), true, raw)
end

local function resolve(raw)
    local path = pathOf(raw)
    if not path then
        publish("", false, raw)
        return
    end
    local dir = dirOf(path)
    if not dir then
        publish(path, true, raw)
        return
    end
    local ok, _ = pcall(run, "ls", { "-1", dir }, function(out, code)
        if code ~= 0 then
            publish(path, true, raw)
            return
        end
        local candidates = {}
        for line in (out or ""):gmatch("[^\n]+") do
            candidates[#candidates + 1] = line
        end
        choose(candidates, dir, raw)
    end)
    if not ok then publish(path, true, raw) end
end

local function schedule(raw)
    if timer then cancel(timer) end
    timer = after(DEBOUNCE_MS, function()
        timer = nil
        resolve(raw)
    end)
end

-- The track identity is what the QS keys on: a new title/artist is a new
-- picture, and the art URL alone changing is a new picture too.
sys.watch("media", function(media)
    if type(media) ~= "table" then return end
    local key = tostring(media.title or "") .. "|" .. tostring(media.artist or "")
    if key == lastKey then return end
    lastKey = key
    schedule(media.art)
end)
