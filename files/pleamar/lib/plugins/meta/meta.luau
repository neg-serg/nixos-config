-- meta.luau — the logic of the track-metadata plugin (see meta.plm).
--
-- Legacy: files/quickshell/Services/MusicMeta.qml, which reads the **player's
-- own metadata** first (genre, album artist, composer, date, track number) and
-- only then opens the file for what the player cannot say (codec, depth, sample
-- rate, bitrate). This plugin does the same, through MPRIS instead of one
-- hard-wired player:
--
--   media changes  ->  `playerctl -a metadata --format …`: every player, one
--                      line each; the playing one (else the paused one) answers;
--   its `xesam:url` ->  `ffprobe -v quiet -print_format json … <path>`;
--   ffprobe fails  ->  `mediainfo --Output=JSON <path>`;
--   no url at all   ->  the tags stay as MPRIS reported them and only the
--                      quality line is empty (a player that streams or does not
--                      publish a url — mpd's own bridge is one — still has
--                      genre and the year, and that is what the card shows).
--
-- Permissions are the plugin's own: playerctl, ffprobe, mediainfo; media.

local lastKey = nil
local lastFile = nil
local introspecting = false

-- Declared before `clear()` uses it: a local is bound where it is written, and
-- `clear()` sits above the tags.
local publish_rows

-- What only a file can say. Cleared whenever the tags change and the new track
-- has no readable file, so a stale codec never sits under a new title.
local function clear_file()
    fact.bitDepth = 0
    fact.sampleRate = 0
    fact.bitrateKbps = 0
    fact.channels = 0
    fact.sizeBytes = 0
    text.codec = ""
    text.container = ""
    text.file = ""
    text.summary = ""
end

-- Nothing playing at all: every fact and text goes, the card falls back to what
-- the service itself reports.
local function clear()
    clear_file()
    fact.trackNo = 0
    fact.discNo = 0
    fact.year = 0
    text.genre = ""
    text.label = ""
    text.albumArtist = ""
    text.composer = ""
    publish_rows()
end

-- Tags arrive as "6" or "6/12": the leading number is the one that matters.
local function number(value)
    if value == nil then return 0 end
    local parsed = tonumber(value) or tonumber(tostring(value):match("^%s*(%d+)"))
    if not parsed then return 0 end
    return math.floor(parsed + 0.5)
end

local function tag(tags, name)
    if type(tags) ~= "table" then return "" end
    return tostring(tags[name] or tags[name:lower()] or tags[name:upper()] or "")
end

-- The QS formatting, kept short: the codec in capitals, the depth/sample rate
-- when the file reports them, the bitrate in kbps.
local function summary()
    local parts = {}
    if text.codec ~= "" then
        parts[#parts + 1] = text.codec:upper()
    end
    if fact.bitDepth > 0 and fact.sampleRate > 0 then
        parts[#parts + 1] = fact.bitDepth .. "/" .. string.format("%.1f", fact.sampleRate / 1000):gsub("%.0$", "")
    elseif fact.sampleRate > 0 then
        parts[#parts + 1] = string.format("%.1f kHz", fact.sampleRate / 1000):gsub("%.0 ", " ")
    end
    if fact.bitrateKbps > 0 then
        parts[#parts + 1] = fact.bitrateKbps .. " kbps"
    end
    if text.container ~= "" then
        parts[#parts + 1] = text.container
    end
    text.summary = table.concat(parts, " · ")
end

-- The tag rows a card draws under the title, in the QS order and with the QS
-- glyphs. Filled here, not in the scene: only the logic can ask whether a text
-- is empty, and an icon with nothing after it is the defect that rule exists to
-- avoid.
function publish_rows()
    local rows = {}
    local function add(glyph, value)
        if value ~= nil and tostring(value) ~= "" then
            rows[#rows + 1] = { glyph = glyph, value = tostring(value) }
        end
    end
    add("category", text.genre)
    if fact.year > 0 then add("calendar_month", fact.year) end
    add("sell", text.label)
    add("piano", text.composer)
    add("high_quality", text.summary)
    model.rows = rows
end

local function publishFfprobe(data)
    local stream, format = nil, {}
    if type(data.streams) == "table" then
        for _, candidate in ipairs(data.streams) do
            if type(candidate) == "table" and candidate.codec_type == "audio" then
                stream = candidate
                break
            end
        end
    end
    if type(data.format) == "table" then format = data.format end
    if not stream then
        clear()
        return false
    end
    local tags = format.tags or stream.tags or {}
    fact.bitDepth = number(stream.bits_per_raw_sample or stream.bits_per_sample)
    fact.sampleRate = number(stream.sample_rate)
    fact.channels = number(stream.channels)
    fact.bitrateKbps = math.floor(number(stream.bit_rate or format.bit_rate) / 1000 + 0.5)
    fact.sizeBytes = number(format.size)
    fact.trackNo = number(tag(tags, "track") ~= "" and tag(tags, "track") or tag(tags, "tracknumber"))
    fact.discNo = number(tag(tags, "disc") ~= "" and tag(tags, "disc") or tag(tags, "discnumber"))
    local date = tag(tags, "date")
    fact.year = number(date:match("(%d%d%d%d)"))
    text.codec = tostring(stream.codec_name or "")
    text.container = tostring(format.format_name or ""):gsub(",.*$", "")
    text.genre = tag(tags, "genre")
    text.label = tag(tags, "label")
    text.albumArtist = tag(tags, "album_artist") ~= "" and tag(tags, "album_artist") or tag(tags, "albumartist")
    text.composer = tag(tags, "composer")
    summary()
    publish_rows()
    return true
end

local function publishMediainfo(data)
    local track = nil
    if type(data.media) == "table" and type(data.media.track) == "table" then
        for _, candidate in ipairs(data.media.track) do
            if type(candidate) == "table" and candidate["@type"] == "Audio" then
                track = candidate
                break
            end
        end
    end
    if not track then
        clear()
        return false
    end
    fact.bitDepth = number(track.BitDepth)
    fact.sampleRate = number(track.SamplingRate)
    fact.channels = number(track.Channels)
    fact.bitrateKbps = math.floor(number(track.BitRate) / 1000 + 0.5)
    fact.sizeBytes = number(track.FileSize)
    fact.trackNo = number(track.Track_Position)
    text.codec = tostring(track.Format or "")
    text.container = tostring(track.Format_Profile or "")
    text.genre = tostring(track.Genre or "")
    text.label = tostring(track.Label or "")
    text.albumArtist = tostring(track.Album_Performer or "")
    text.composer = tostring(track.Composer or "")
    summary()
    publish_rows()
    return true
end

local function introspect(path)
    if introspecting then return end
    introspecting = true
    local ok = pcall(run, "ffprobe",
        { "-v", "quiet", "-print_format", "json", "-show_streams", "-show_format", path },
        function(out, code)
            if code == 0 and out then
                local decoded, data = pcall(function() return json.decode(out) end)
                if decoded and publishFfprobe(data) then
                    introspecting = false
                    return
                end
            end
            -- mediainfo takes the same path and answers JSON too (the QS
            -- fallback chain, one step shorter: sox --i is not ported).
            local okInfo = pcall(run, "mediainfo", { "--Output=JSON", path }, function(infoOut, infoCode)
                if infoCode == 0 and infoOut then
                    local decoded, data = pcall(function() return json.decode(infoOut) end)
                    if decoded and publishMediainfo(data) then
                        introspecting = false
                        return
                    end
                end
                clear()
                introspecting = false
            end)
            if not okInfo then
                clear()
                introspecting = false
            end
        end)
    if not ok then
        clear()
        introspecting = false
    end
end

-- MPRIS, asked of every player at once: one line each, the fields in the order
-- below. `--format` keeps one call per update instead of one per field.
local MPRIS_FORMAT = "{{status}}\t{{xesam:title}}\t{{xesam:artist}}\t{{xesam:album}}"
    .. "\t{{xesam:genre}}\t{{xesam:albumArtist}}\t{{xesam:composer}}"
    .. "\t{{xesam:contentCreated}}\t{{xesam:trackNumber}}\t{{xesam:url}}"

local function decode(path)
    return (path:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- A url a file can be read from, or nothing: a stream has no file behind it, and
-- a player that publishes no url (mpd's bridge does not) leaves the quality line
-- empty instead of guessing at a path.
local function url_to_path(url)
    if type(url) ~= "string" or url == "" then return nil end
    if url:match("^https?://") or url:match("^icy://") then return nil end
    if url:sub(1, 7) == "file://" then return decode(url:sub(8)) end
    if url:sub(1, 1) == "/" then return url end
    return nil
end

local function fields(line)
    local out = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do
        out[#out + 1] = field
    end
    return out
end

-- The playing player answers; with none playing, the paused one (the same choice
-- the `media` service makes, and what QS's `hasPlayer` means).
local function refresh()
    local ok = pcall(run, "playerctl", { "-a", "metadata", "--format", MPRIS_FORMAT }, function(out)
        -- Every player is kept, with its state, and the choice is made after:
        -- a browser tab that is paused has no tags at all, and it used to win
        -- over the music player that does — the card then showed a title and no
        -- genre while `playerctl` was answering with both.
        local rows = {}
        if type(out) == "string" then
            for line in out:gmatch("[^\n]+") do
                local row = fields(line)
                if row[1] == "Playing" or row[1] == "Paused" or row[1] == "Stopped" then
                    rows[#rows + 1] = row
                end
            end
        end
        local function rank(state)
            if state == "Playing" then return 1 elseif state == "Paused" then return 2 else return 3 end
        end
        local function tagged(row)
            return (row[5] or "") ~= "" or (row[8] or "") ~= "" or (row[6] or "") ~= ""
        end
        -- A tagged row first, whatever its state; among equals, the one closest
        -- to playing.
        table.sort(rows, function(a, b)
            local ta, tb = tagged(a), tagged(b)
            if ta ~= tb then return ta end
            return rank(a[1]) < rank(b[1])
        end)
        -- `Stopped` counts too: a player with a track loaded but not playing has
        -- its tags, and the card still draws that track.
        local row = rows[1]
        if not row then
            lastFile = nil
            clear()
            return
        end

        -- The tags MPRIS itself carries (the QS first source). The year comes
        -- out of `xesam:contentCreated`, a full date.
        text.genre = row[5] or ""
        text.albumArtist = row[6] or ""
        text.composer = row[7] or ""
        fact.trackNo = number(row[9])
        local created = row[8] or ""
        fact.year = tonumber(created:match("(%d%d%d%d)")) or 0

        local path = url_to_path(row[10])
        if not path then
            lastFile = nil
            clear_file()
            text.file = ""
            publish_rows()
            return
        end
        if path == lastFile then
            publish_rows()
            return
        end
        lastFile = path
        text.file = path
        publish_rows()
        introspect(path)
    end)
    if not ok then clear() end
end

local function on_media(media)
    if type(media) ~= "table" then return end
    local key = tostring(media.title or "") .. "|" .. tostring(media.artist or "")
    if key == lastKey then return end
    lastKey = key
    refresh()
end

sys.watch("media", on_media)

-- The watch only reports *changes*: a track that was already playing when the
-- scene started never produces one, and the card would sit with no tags at all
-- until the next track — which reads as "the plugin does nothing". Ask once at
-- load and keep asking every three seconds until the tags are there, then stop.
local asked, current = pcall(sys.ask, "media")
if asked and type(current) == "table" then on_media(current) end

every(3000, function()
    if lastFile or #model.rows > 0 then return end
    refresh()
end)
