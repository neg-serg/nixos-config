-- meta.luau — the logic of the track-metadata plugin (see meta.plm).
--
-- Legacy: files/quickshell/Services/MusicMeta.qml, minus `sox --i`.
--
--   media (title/artist) changes  ->  `mpc -f '%file%' current` for the file,
--                                     resolved against the music root;
--   file changes                  ->  `ffprobe -v quiet -print_format json
--                                     -show_streams -show_format <path>`;
--   ffprobe fails                 ->  `mediainfo --Output=JSON <path>`;
--   nothing to inspect            ->  every fact cleared (a stream is a stream).
--
-- The music root is the plugin's own settings file, `meta.json` in its folder,
-- with the QS MusicManager's directory as the default. A plugin's folder is the
-- only place its files service can read, so the setting lives there and the
-- scene keeps out of it.
--
-- Permissions are the plugin's own: mpc, ffprobe, mediainfo; media, files.

local SETTINGS = "meta.json"
local DEFAULT_ROOT = "/home/neg/music"

local root = DEFAULT_ROOT
local lastKey = nil
local lastFile = nil
local introspecting = false

local function clear()
    fact.bitDepth = 0
    fact.sampleRate = 0
    fact.bitrateKbps = 0
    fact.channels = 0
    fact.sizeBytes = 0
    fact.trackNo = 0
    fact.discNo = 0
    fact.year = 0
    text.codec = ""
    text.container = ""
    text.genre = ""
    text.label = ""
    text.albumArtist = ""
    text.composer = ""
    text.file = ""
    text.summary = ""
end

local function settings()
    local ok, state = pcall(sys.ask, "files.read", SETTINGS, "json")
    if ok and type(state) == "table" and type(state.root) == "string" and state.root ~= "" then
        root = state.root
    end
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

-- `mpc -f '%file%' current` is relative to music_directory; `current` is empty
-- when nothing is loaded, which clears the line (no file, nothing to say).
local function refresh()
    local ok, _ = pcall(run, "mpc", { "-f", "%file%", "current" }, function(out, code)
        local relative = nil
        if code == 0 and type(out) == "string" then
            relative = out:match("^%s*(.-)%s*$")
            if relative == "" then relative = nil end
        end
        if not relative then
            lastFile = nil
            clear()
            return
        end
        if relative == lastFile then return end
        lastFile = relative
        text.file = relative
        introspect(root .. "/" .. relative)
    end)
    if not ok then clear() end
end

settings()

sys.watch("media", function(media)
    if type(media) ~= "table" then return end
    local key = tostring(media.title or "") .. "|" .. tostring(media.artist or "")
    if key == lastKey then return end
    lastKey = key
    refresh()
end)
