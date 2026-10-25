-- bar.luau — the thin logic behind bar.plm.
--
-- The declarative scene draws, animates and reads its services on its own; only
-- what no rule can do is here: merge the bar's settings from the scene's own
-- folder and command the services. Nothing here paints or knows coordinates.

local FILE = "settings.json"

-- Defaults live in code; the file holds what the user changed. The frozen keys
-- of INTERFACES §6.3 that this slice cannot apply yet (height, fontScale,
-- animations, startupClean, monitorScale) are left untouched in the file.
local D = {
    edge = "bottom", -- top | bottom; bottom on trantor
    scale = 1.0,     -- user multiplier on top of ui and the per-monitor fit
}

-- The widgets this slice draws; `widgets` in the file is read as the visible
-- set. An order cannot be applied at runtime (the scene paints in the order it
-- is written), and entries this slice does not know yet (pill, keyboard, media,
-- …) are kept in the file for the slices that do.
local WIDGETS = { "clock", "workspaces", "keyboard", "pill", "network", "sysmon", "weather", "media", "mpd", "volume", "mic", "genelec" }

-- The canonical clamp of INTERFACES §6.1: a wrong type and NaN keep the default.
local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

-- Read only: a missing file is the defaults; a broken one keeps the defaults
-- too, and says so (`pcall`: `files.read` raises when the JSON cannot be read).
-- Reads never write (INTERFACES §6.1).
local function read_file()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if not ok then
        log("settings: unreadable, the defaults are used")
        return {}
    end
    if type(got) == "table" then return got end
    return {}
end

local function apply(raw)
    local edge = raw.edge
    if edge ~= "top" and edge ~= "bottom" then edge = D.edge end
    fact.bar_edge = edge

    fact.user_scale = num(raw.scale, 0.5, 2.0, D.scale)

    local wanted = nil
    if type(raw.widgets) == "table" then
        wanted = {}
        for i = 1, math.min(#raw.widgets, 24) do
            if type(raw.widgets[i]) == "string" then wanted[raw.widgets[i]] = true end
        end
    end
    for _, name in ipairs(WIDGETS) do
        fact["widget." .. name] = (wanted == nil) or (wanted[name] == true)
    end
end

apply(read_file())

-- An editor, or another copy of the scene, changed the file: read it again and
-- take the new values, clamped the same way (the file is the source, so the
-- change is honoured live).
sys.watch("files:" .. FILE, function()
    apply(read_file())
end)

-- Writes arrive with the settings UI of a later slice: mutate `raw` (`raw[key]
-- = value`) and `sys.call("files.write", FILE, raw)`, never a table built from
-- scratch, so keys another version put there survive (INTERFACES §6.1).

-- ---------------------------------------------------------------- commands
-- A workspace tab was pressed: show that workspace.
-- (permissions: "workspaces", "workspaces.focus")
on("focus_workspace", function(id)
    sys.call("workspaces.focus", id)
end)

-- A player is there (the QS `hasPlayer`): the capsule shows only then. The
-- scene cannot compare `media.player` with "" itself — the language compares
-- numbers only — so the logic decides and hands over a fact.
-- (permissions: "media")
-- QS shows the capsule only while a player has something to play: `hasPlayer
-- && (isPlaying || isPaused)`. A player that is there but stopped (mpc with an
-- empty queue) is not enough, and that is what made the port draw a capsule
-- the reference did not have.
-- A pause has no field of its own: the media service answers `playing` and
-- nothing about paused. QS keeps the capsule through a pause (`isPaused`), so
-- the port holds `media.present` for a while after `playing` was last true —
-- long enough to cover a pause, short enough that a player left stopped lets
-- the capsule go. The proper fix is a `paused` field in the service
-- (~/src/pleamar, outside this tree); this is the cheap stand-in.
local MEDIA_HOLD_MS = 10000
local mediaShown = false
local mediaHold = nil

local function showMedia(on)
    if mediaShown == on then return end
    mediaShown = on
    fact["media.present"] = on
end

-- ------------------------------------------------- cover accent (QS MusicManager)
-- QS samples the current cover with Helpers/AccentSampler.js — the mean of its
-- saturated pixels, two passes — and paints the time's brackets and separator with
-- it. A colour is not a fact, so the scene reads it from an imported file the way
-- it reads theme.plm: this writes ~/.config/pleamar/art.plm and the running scene
-- re-reads that import when it changes.
--
-- It lives here and not in the Cover plugin, because that plugin's logic is
-- approved for `ls` alone: sampling wants magick, and a plugin asking for a new
-- command stops the scene until somebody approves it by hand. The bar runs dash
-- already.
local ACCENT_SCRIPT = [[
set -e
art="$1"
[ -n "$art" ] || exit 0
case "$art" in http*|"") exit 0 ;; esac
art="${art#file://}"
[ -r "$art" ] || exit 0
hex=$(magick "$art" -resize 48x48! -depth 8 txt:- 2>/dev/null | awk '
  $2 ~ /^\(/ {
    t = $2; gsub(/[()]/, "", t); n = split(t, a, ",")
    if (n < 3) next
    r = a[1] + 0; g = a[2] + 0; b = a[3] + 0
    hi = r; if (g > hi) hi = g; if (b > hi) hi = b
    lo = r; if (g < lo) lo = g; if (b < lo) lo = b
    sat = hi - lo; lum = (r + g + b) / 3
    if (sat >= 10 && lum >= 20 && lum <= 235) { r1 += r; g1 += g; b1 += b; n1++ }
    if (sat >= 8  && lum >= 20 && lum <= 240) { r2 += r; g2 += g; b2 += b; n2++ }
  }
  END {
    if (n1 > 0)      printf "#%02x%02x%02x", r1 / n1, g1 / n1, b1 / n1
    else if (n2 > 0) printf "#%02x%02x%02x", r2 / n2, g2 / n2, b2 / n2
  }')
[ -n "$hex" ] || exit 0
mkdir -p "$HOME/.config/pleamar"
printf '// generated from the cover\nlibrary Art strict {\n\n    let cover_accent = %s\n}\n' "$hex" > "$HOME/.config/pleamar/art.plm"
]]

local lastArt = nil

local function accentFrom(art)
    if type(art) ~= "string" or art == "" or art == lastArt then return end
    lastArt = art
    run("dash", { "-c", ACCENT_SCRIPT, "accent", art })
end

local mediaPos = 0
local mediaPlaying = false

sys.watch("media", function(m)
    local player, playing = nil, false
    if type(m) == "table" then
        accentFrom(m.art)
        player = m.player
        playing = m.playing == true
    end
    local has = (type(player) == "string") and (player ~= "")
    -- No player at all: the capsule goes at once, like QS's `hasPlayer`.
    if not has then
        if mediaHold then
            cancel(mediaHold)
            mediaHold = nil
        end
        showMedia(false)
        return
    end
    -- A player that is there is enough: QS's Media.qml keeps the capsule for
    -- `isPlaying || isPaused`, and the paused half is what the reference shows
    -- while the queue sits where the owner left it. The hold this used to arm
    -- (ten seconds after a pause, then gone) was the one visible difference —
    -- the cover disappeared from the bar whenever the music did.
    --
    -- The media service reports `playing`, not a playback state, so "paused" and
    -- "stopped" cannot be told apart here. A track that is still loaded is the
    -- signal: an empty title means the queue let go of the song, and that is
    -- when the capsule goes.
    local title = (type(m.title) == "string") and m.title or ""
    local artist = (type(m.artist) == "string") and m.artist or ""
    -- How wide the track's box has to be, in design px. QS sizes the capsule by
    -- `trackContainer.implicitWidth`, which is the title text's own width (Media.qml:103-106),
    -- so the plate hugs the string it holds; the port's fixed 168 left a hole after every
    -- short one and cut long ones early. Iosevka's advance is half an em, so at the
    -- capsule's 14 design px a character is 7; 40 to 200 is the range the reference's own
    -- marquee works in.
    local track = (artist ~= "" and title ~= "") and (artist .. " — " .. title) or title
    local n = utf8.len(track) or #track
    fact.media_w = math.min(200, math.max(40, n * 7))
    if mediaHold then
        cancel(mediaHold)
        mediaHold = nil
    end
    showMedia(title ~= "")
end)

-- The engine reports `media.position` when the player says something, and never polls it, so
-- the bar's clock would stand still while the track plays. The logic keeps its own: a second
-- per tick while the player is playing, resynced from every report.
sys.watch("media", function(m)
    if type(m) ~= "table" then return end
    if type(m.position) == "number" then mediaPos = math.floor(m.position) end
    mediaPlaying = m.playing == true
    fact["media.pos"] = mediaPos
end)

every(1000, function()
    if not mediaPlaying then return end
    mediaPos = mediaPos + 1
    fact["media.pos"] = mediaPos
end)

-- The transport strip: the three glyph buttons of the media capsule.
-- (permissions: "media.*")
on("media_toggle", function()
    sys.call("media.toggle")
end)

on("media_next", function()
    sys.call("media.next")
end)

-- The transport pill rides out to the left of the capsule, and the cursor has to be
-- able to cross the gap between them: QS holds it open with a 300 ms closeGrace
-- (MediaTransport.qml), and the scene can only say "entered" and "left", so the
-- timer lives here.
local HOVER_HOLD_MS = 300
local hoverTimer = nil

on("media_hover", function(hot)
    if hot then
        if hoverTimer then cancel(hoverTimer) end
        hoverTimer = nil
        fact["media.hot"] = true
        return
    end
    if not fact["media.hot"] then return end
    if hoverTimer then cancel(hoverTimer) end
    hoverTimer = after(HOVER_HOLD_MS, function()
        hoverTimer = nil
        fact["media.hot"] = false
    end)
end)

on("media_prev", function()
    sys.call("media.previous")
end)

-- The bar opens drawers in the `panels` scene: the cover opens the now-playing
-- card, the network capsule opens the flow dashboard — QS's two side panels.
-- That scene is not resident (its only surface is the drawer itself), so it
-- exits a couple of seconds after the last drawer closes; starting the unit and
-- saying where to go is one step. The fact has to arrive *after* the scene has
-- loaded: a `--say` that lands while it is still starting is overwritten by its
-- own defaults (drawer = none), no surface opens, and the scene exits. So wait
-- past the load, then keep asserting the fact for a moment — it is a state, not
-- a press, and saying it twice costs nothing.
local function open_drawer(name)
    run("dash", {
        "-c",
        "systemctl --user start pleamar-panels.service; sleep 1.1; "
            .. "for i in $(seq 1 10); do "
            .. "pleamar --say panels 'fact drawer " .. name .. "' >/dev/null 2>&1 || break; "
            .. "sleep 0.15; done",
    })
end

on("open_media_panel", function() open_drawer("media") end)
on("open_network_panel", function() open_drawer("network") end)

-- The wheel turned over the volume capsule: one step per notch (+ is upwards;
-- the step is the frozen QS one, not yet a settings key).
-- (permissions: "audio", "audio.*")
on("wheel_volume", function(notches)
    sys.call("audio.step", notches * 0.05)
end)

-- The capsule was pressed: `audio.mute` with no argument flips the sink's
-- silence (pleamar's pulse.rs: set_mute(..., !muted)), so the toggle needs no
-- state here. (permissions: "audio", "audio.*")
on("toggle_mute", function()
    sys.call("audio.mute")
end)

-- ------***---------------------- audio capsules
-- QS AudioEndpointCapsule hides itself for two reasons, and the bar has to do
-- the same or the right end is heavier than the reference:
--   · the endpoint is muted (autoHideWhenMuted) — for the microphone that is
--     the whole story;
--   · the sink sits at 100 %: `fullHideTimer` (panel.volume.fullHideMs = 800)
--     collapses the capsule once it has been there that long, and a level that
--     leaves 100 % brings it straight back.
-- The pill text and the icon stay the scene's (`audio.volume`/`audio.input`);
-- only the presence is decided here, because it needs timers and the two
-- fields the language cannot compare.
local FULL_HIDE_MS = 800
local fullHide = nil

local function hideVolume()
    fullHide = nil
    fact["vol.shown"] = false
end

local function audioChanged(a)
    if type(a) ~= "table" then return end
    -- The glyph follows the state, not a constant: what the capsule shows is the first
    -- thing that should say "muted".
    text["mic.glyph"] = (a.input_muted == true) and "mic_off" or "mic"
    local lvl = tonumber(a.volume) or 0
    text["vol.glyph"] = (a.muted == true) and "volume_off"
        or (lvl < 0.5 and "volume_down" or "volume_up")
    fact["mic.shown"] = a.input_muted ~= true
    if a.muted == true then
        if fullHide then cancel(fullHide) end
        hideVolume()
        return
    end
    local volume = tonumber(a.volume) or 0
    if volume >= 0.995 then
        if fullHide == nil then fullHide = after(FULL_HIDE_MS, hideVolume) end
    else
        if fullHide then cancel(fullHide) end
        fullHide = nil
        fact["vol.shown"] = true
    end
end

sys.watch("audio", audioChanged)

-- A press on the microphone capsule: `audio.input_mute` flips the source's
-- silence (QS Microphone.toggleMicMute). (permissions: "audio", "audio.*")
on("toggle_mic", function()
    sys.call("audio.input_mute")
end)

-- ------------------------------------------------------------ workspaces
-- QS's WsIndicator draws ONE capsule: the active workspace's icon and its
-- name. The icon is the Nerd Font glyph `Bar/Icons/workspaces/icon-map.json`
-- gives that workspace's slug (the tree renders them from the SVGs generated
-- out of the same codepoints), and the name is what follows the `𐌸:`-style
-- prefix Hyprland stores in the workspace name.
--
-- Both are text, so they travel to the scene as `text` declarations; the map
-- is by workspace id (the manifest's own numbering), which is what the bar
-- sees for a workspace that was never renamed.
local WS_GLYPH = {
    [1] = "\u{EA85}",  -- term
    [2] = "\u{F269}",  -- web
    [3] = "\u{F4B0}",  -- dev
    [4] = "\u{F1B7}",  -- games
    [5] = "\u{F15C}",  -- doc
    [6] = "\u{F008}",  -- vid
    [7] = "\u{273D}",  -- obs
    [8] = "\u{F03E}",  -- pic
    [9] = "\u{EA7A}",  -- vm
    [10] = "\u{F1CB}", -- wine
    [12] = "\u{F001}", -- daw
    [13] = "\u{F0ED}", -- dw
    [14] = "\u{F11C}", -- keyboard
    [15] = "\u{F086}", -- im
    [16] = "\u{F019}", -- remote
    [17] = "\u{F24D}", -- notes
    [18] = "\u{F1DE}", -- vital
    [19] = "\u{F02C1}", -- rack
}

-- The name as Hyprland stores it, minus a leading private-use glyph — the rule QS
-- keeps in Helpers/WorkspaceName.js (`restAfterIcon`): one leading glyph, nothing
-- else. This used to cut everything up to the first colon, so a workspace the owner
-- named "p:term" was drawn as "term" and the port disagreed with the reference about
-- a name it had no business editing (measured on the bars: QS "p:term", here "term").
local function label_of(name)
    if type(name) ~= "string" or name == "" then return "" end
    local ok, cp = pcall(utf8.codepoint, name, 1)
    if ok and cp >= 0xE000 and cp <= 0xF8FF then
        local after = utf8.offset(name, 2) or (#name + 1)
        name = name:sub(after)
    end
    return (name:gsub("^%s+", ""))
end

-- The workspace names the owner set carry an Old Italic letter in front
-- (`𐌰:term`), and no face the bar uses has it: Iosevka and FiraCode both fall
-- back, fontconfig answers U+10330 with Code2001 while cosmic-text picks another
-- font, so the same name came out with two shapes. The letter is handed to the
-- scene on its own, to be drawn in Code2001 — the face Qt lands on for it.
local function split_lead(name)
    if type(name) ~= "string" or name == "" then return "", "" end
    local ok, cp = pcall(utf8.codepoint, name, 1)
    if ok and cp >= 0x10300 and cp <= 0x1034F then
        local after = utf8.offset(name, 2) or (#name + 1)
        return name:sub(1, after - 1), name:sub(after)
    end
    return "", name
end

local function workspacesChanged(w)
    if type(w) ~= "table" or type(w.list) ~= "table" then return end
    for _, ws in ipairs(w.list) do
        if type(ws) == "table" and ws.active == true then
            local lead, rest = split_lead(label_of(ws.name))
            -- A workspace with no name (or a name that is only a private-use glyph) drew an
            -- empty plate; the reference falls back to the number, and so does this.
            if rest == "" then rest = tostring(ws.id) end
            text.ws_lead = lead
            text.ws_label = rest
            text.ws_icon = WS_GLYPH[tonumber(ws.id) or -1] or ""
            return
        end
    end
    text.ws_lead = ""
    text.ws_label = ""
    text.ws_icon = ""
end

sys.watch("workspaces", workspacesChanged)

-- ------------------------------------------------------------- tooltips
-- QS gives every capsule a PanelTooltip whose text TooltipText.compose builds
-- out of a title, a value and a list of hints. The scene says which capsule the
-- cursor is on (`emit tip(n)`), and the line is written here, because only the
-- logic can compose text.
-- (permissions: "clock", nothing else — the rest it already watches)
local tipClock = ""

sys.watch("clock", function(c)
    if type(c) == "table" and type(c.date) == "string" then tipClock = c.date end
end)

local function tip_line(i)
    if i == 0 then
        return tipClock ~= "" and tipClock or "Clock"
    elseif i == 1 then
        return "Workspace " .. (text.ws_label ~= "" and text.ws_label or "?")
    elseif i == 2 then
        return "Keyboard layout " .. (text.kb_layout ~= "" and text.kb_layout or "?")
    elseif i == 3 then
        -- ConnUi prints the pair as "<rx> / <tx>"; the tooltip says both.
        return "Throughput " .. (text.net_rx ~= "" and (text.net_rx .. text.net_rx_unit) or "--")
            .. " down, " .. (text.net_tx ~= "" and (text.net_tx .. text.net_tx_unit) or "--") .. " up"
    elseif i == 4 then
        local cpu = math.floor((fact.cpu or 0) * 100 + 0.5)
        local ram = math.floor((fact.ram or 0) * 100 + 0.5)
        return string.format("CPU %d %%, RAM %d %%", cpu, ram)
    elseif i == 6 then
        -- The media card in the reference: title — artist, the album, the player. Three lines
        -- to the others' one, and the card is sized for that.
        local l1 = (media.title or "") .. ((media.artist and media.artist ~= "") and (" — " .. media.artist) or "")
        local l2 = media.album or ""
        local l3 = (media.player and media.player ~= "") and media.player or ""
        return table.concat({ l1 ~= "" and l1 or "Nothing playing", l2, l3 }, "\n")
    elseif i == 5 then
        local parts = { "Weather" }
        if text["weather.temp"] ~= "" then parts[#parts + 1] = text["weather.temp"] end
        if text["weather.hum"] ~= "" then parts[#parts + 1] = text["weather.hum"] end
        if text["weather.wind"] ~= "" then parts[#parts + 1] = text["weather.wind"] .. " m/s" end
        return table.concat(parts, " · ")
    end
    return ""
end

on("tip", function(i)
    text.tip_body = tip_line(i or 0)
end)

-- ---------------------------------------------------------------- tray
-- The icons come from the StatusNotifier host as they are: a record's fields are
-- `key`, `title`, `icon` (a name or a path) with the rest ignored, so the list
-- goes straight into the model. A click comes back as the record's INDEX — an
-- event carries a number — so the keys are kept here, in the same order.
local trayItems = {}

sys.watch("tray", function(list)
    trayItems = (type(list) == "table") and list or {}
    model.icons = trayItems
end)

-- QS's left click on an icon is `modelData.activate()`, which is what
-- `tray.activate` asks the item for. The right button is the item's own menu, and
-- the reference's SystemTray asks the application for it rather than drawing one:
-- `tray.context` is that request, so this scene needs no popup surface for it. A
-- drawn menu (`sys.ask("tray.menu", key)` as a tree, `lib/menu.plm` painting it)
-- is the parity step that still waits for a popup here.

on("tray_press", function(index)
    fact.tray_open = false
    local item = trayItems[(index or 0) + 1]
    if type(item) ~= "table" or type(item.key) ~= "string" then return end
    sys.call("tray.activate", item.key)
end)

-- The right button on an icon: the item's own menu, drawn by the bar. The scene hands over
-- the record's index; the key that names the bus name and the object path is looked up here.
-- A second press closes it, and a left click does too.
-- The engine wants the icon's key *and* the line's id (`tray.menu_click`, tray.rs:command),
-- and it raises when it does not get both — which is why a press used to leave the menu open:
-- the handler died before it could close it.
on("tray_click", function(n)
    log("TRAYCLICK " .. tostring(n))
    local at = tonumber(n) or 0
    local key = text["tray_key"]
    local id = fact["tm.id." .. at]
    fact.tray_open = false
    if type(key) == "string" and key ~= "" and type(id) == "number" and id > 0 then
        -- Wrapped: a failing call must not roll back `tray_open` — a menu that stays up after a
        -- press is worse than a click that did nothing.
        local ok, err = pcall(function() sys.call("tray.menu_click", key, id) end)
        if not ok then log("TRAYCLICK failed: " .. tostring(err)) end
    end
end)

-- Esc closes the menu: the surface asks for the keyboard while it is open (`keyboard:
-- exclusive while tray_open`), so the key reaches this scene and not the application under it.
on("key", function(name)
    if name == "Escape" and fact.tray_open then
        fact.tray_open = false
    end
end)

on("tray_close", function()
    log("TRAYCLOSE")
    fact.tray_open = false
end)

on("tray_menu", function(index)
    local at = index or 0
    if fact.tray_open then
        fact.tray_open = false
        return
    end
    local key = text["tray_key"]
    if type(key) ~= "string" or key == "" then return end
    local ok, tree = pcall(function() return sys.ask("tray.menu", key) end)
    if not ok then
        text["tm.1"] = tostring(tree)
        fact["tm.count"] = 1
        fact.tray_open = true
        return
    end
    if type(tree) ~= "table" or #tree == 0 then
        sys.call("tray.context", key)
        return
    end
    local shown = 0
    local widest = 0
    for _, it in ipairs(tree) do
        if shown >= 8 then break end
        local label = (type(it) == "table" and it.label) or ""
        local sep = type(it) == "table" and it.separator == true
        fact["tm.sep." .. (shown + 1)] = sep
        shown = shown + 1
        text["tm." .. shown] = tostring(label)
        widest = math.max(widest, #label)
        fact["tm.id." .. shown] = (type(it) == "table" and tonumber(it.id)) or 0
    end
    for i = shown + 1, 8 do text["tm." .. i] = "" end
    fact["tm.count"] = shown
    fact["tm.panel_h"] = 12 + 20 * shown
    -- 6.5 px per character at size 13, plus the plate's 10 px of padding on each side, clamped
    -- to what the surface can hold.
    fact["tm.w"] = math.min(300, math.max(120, math.floor(widest * 6.5) + 28))
    fact.tray_open = true
end)

-- ----------------------------------------------------------- throughput
-- QS's ConnectivityState.throughputText: the bar shows receive over transmit,
-- each as three digits and a decimal (ConnUi.formatRxText / formatTxText).
-- Two samples of /proc/net/dev, every timers.genericTickMs (2000), summing
-- every interface but the loopback.
--
-- The interval is the timer's, not a clock reading: the sandbox closes `os`, so
-- the logic has no wall clock of its own. A missed tick makes the figure read
-- low for one sample, nothing worse.
local through = nil

-- ConnUi.formatScaledKiBps: KiB/s auto-scaled to K/M/G/T, the integer part
-- zero-padded to three digits and one decimal. QS drops the decimal only when
-- everything is zero ("000").
--
-- The letter is *not* part of the readout: measured on the two bars at the same
-- moment, the reference capsule showed "022.6" beside its link glyph while the
-- port showed "015.7K". The letter belongs to the glyph and to the tooltip.
local UNITS = { "K", "M", "G", "T" }

local function fmt_rate(kib)
    if type(kib) ~= "number" or kib ~= kib or kib < 0 then return "--" end
    local v, unit = kib, 1
    while v >= 999.95 and unit < #UNITS do
        v = v / 1024
        unit = unit + 1
    end
    local fixed = string.format("%.1f", v)
    local int, dec = fixed:match("^(%d+)%.(%d)$")
    if not int then int, dec = fixed, "0" end
    local padded = string.rep("0", 3 - #int) .. int
    if #int > 3 then padded = int end
    local body = (padded == "000" and dec == "0") and padded or (padded .. "." .. dec)
    return body, UNITS[unit] or ""
end

local function sample()
    run("cat", { "/proc/net/dev" }, function(out)
        if type(out) ~= "string" then return end
        local rx, tx = 0, 0
        for line in out:gmatch("[^\n]+") do
            local name, rest = line:match("^%s*([%w%._%-]+):%s*(.*)$")
            if name and name ~= "lo" then
                local fields = {}
                for f in rest:gmatch("%S+") do fields[#fields + 1] = tonumber(f) end
                if fields[1] and fields[9] then
                    rx = rx + fields[1]
                    tx = tx + fields[9]
                end
            end
        end
        if through then
            local rxb, rxu = fmt_rate((rx - through.rx) / 2048)
            local txb, txu = fmt_rate((tx - through.tx) / 2048)
            text.net_rx, text.net_rx_unit = rxb, rxu
            text.net_tx, text.net_tx_unit = txb, txu
            -- QS dims the leading zeros of the integer part (NetClusterCapsule's
            -- _dimLeadingZeros, in textDisabled). A scene's text cannot look at its own
            -- characters, so the count travels as a fact and letter_opacity uses it.
            local function zeros(body)
                local n = 0
                for i = 1, #body do
                    if body:sub(i, i) == "0" then n = n + 1 else break end
                end
                return n
            end
            fact.net_rx_zeros = zeros(rxb)
            fact.net_tx_zeros = zeros(txb)
            -- QS draws the unit letter in the accent and drops "K" altogether, so the
            -- boolean travels too: a component cannot compare a text fact.
            fact.net_rx_show_unit = (rxu ~= "" and rxu ~= "K")
            fact.net_tx_show_unit = (txu ~= "" and txu ~= "K")
        end
        through = { rx = rx, tx = tx }
    end)
end

sample()
every(2000, sample)

-- -------------------------------------------------------------- weather
-- QS WeatherButton: the WMO code as a Material glyph, N °C, water_drop + N %,
-- a navigation arrow turned by the wind direction with the speed beside it, and
-- the moon's phase on the end. open-meteo answers in one to two seconds, which
-- is longer than the parity gate waits, so the answer is cached on disk and the
-- capsule fills from the cache first — the fetch only refreshes it.
--
-- The units are open-meteo's own: `wind_speed_unit=ms` asks for metres per
-- second. Without it the answer is km/h, and the bar's figure would be one
-- / 3.6 too large (WeatherIcons prints what it is given).
-- (permissions: "files", "files.write")
local WEATHER_URL = "https://api.open-meteo.com/v1/forecast"
    .. "?latitude=59.9375&longitude=30.3086"
    .. "&current=temperature_2m,relative_humidity_2m,weather_code,"
    .. "wind_speed_10m,wind_direction_10m&wind_speed_unit=ms"
local WEATHER_CACHE = "weather.json"
local WEATHER_REFRESH_MS = 900000

-- WeatherIcons.materialSymbolForCode, the same ladder.
local function weather_icon(code)
    if code == 0 then return "sunny" end
    if code == 1 or code == 2 then return "partly_cloudy_day" end
    if code == 3 then return "cloud" end
    if code >= 45 and code <= 48 then return "foggy" end
    if code >= 51 and code <= 67 then return "rainy" end
    if code >= 71 and code <= 77 then return "weather_snowy" end
    if code >= 80 and code <= 82 then return "rainy" end
    if code >= 95 and code <= 99 then return "thunderstorm" end
    return "cloud"
end

-- The synodic month from the new moon of 2000-01-06 18:14 UTC — the same
-- reference WeatherIcons.moonAge counts from.
local function moon_phase(epoch)
    if type(epoch) ~= "number" then return 0 end
    local days = (epoch - 947182440) / 86400
    local cycles = days / 29.53059
    local frac = cycles - math.floor(cycles)
    if frac < 0 then frac = frac + 1 end
    return frac
end

local function show_weather(w)
    if type(w) ~= "table" then return end
    local code = tonumber(w.code)
    local temp = tonumber(w.temp)
    if not code or not temp then return end
    local hum = tonumber(w.hum)
    local wind = tonumber(w.wind)
    text["weather.icon"] = weather_icon(code)
    text["weather.temp"] = string.format("%d°C", math.floor(temp + 0.5))
    if hum then text["weather.hum"] = string.format("%d%%", math.floor(hum + 0.5)) end
    -- WeatherIcons.formatWindSpeed: one decimal, no unit in the bar.
    if wind then text["weather.wind"] = string.format("%.1f", wind) end
    -- The arrow points where the wind goes, the reading says where it comes from:
    fact["weather.dir"] = ((tonumber(w.dir) or 0) + 180) % 360
    fact["weather.have"] = true
end

local function weather_cached()
    local ok, got = pcall(function() return sys.ask("files.read", WEATHER_CACHE, "json") end)
    if ok then show_weather(got) end
end

-- The answer is flat enough to read with patterns: each field of `current`
-- appears once as a number, and the copies inside `*_units` are strings.
local function weather_fetch()
    run("curl", { "-s", "--max-time", "4", WEATHER_URL }, function(out, code)
        if code ~= 0 or type(out) ~= "string" or out == "" then return end
        local function n(key)
            return tonumber(out:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)'))
        end
        local w = {
            code = n("weather_code"),
            temp = n("temperature_2m"),
            hum = n("relative_humidity_2m"),
            wind = n("wind_speed_10m"),
            dir = n("wind_direction_10m"),
        }
        if not w.code or not w.temp then return end
        show_weather(w)
        sys.call("files.write", WEATHER_CACHE,
            string.format('{\n  "code": %d,\n  "dir": %d,\n  "hum": %d,\n  "temp": %.1f,\n  "wind": %.1f\n}\n',
                w.code, w.dir or 0, w.hum or 0, w.temp, w.wind or 0))
    end)
end

local function moon_tick()
    run("date", { "+%s" }, function(out)
        local epoch = tonumber(out)
        if epoch then fact["weather.moon"] = moon_phase(epoch) end
    end)
end

weather_cached()
weather_fetch()
moon_tick()
-- The scene's own defaults land after the logic's first pass — the same trap the
-- drawer fact hits — so a phase set here is overwritten by the `0` the scene
-- declared, and the next tick is fifteen minutes away. Say it again once the
-- scene has its feet; the moon was drawing a new moon for a quarter of an hour.
after(1500, moon_tick)
every(WEATHER_REFRESH_MS, weather_fetch)
every(WEATHER_REFRESH_MS, moon_tick)

-- ------------------------------------------------------------- keyboard
-- QS KeyboardLayoutHypr reads the active keymap out of `hyprctl devices -j`;
-- the first keyboard that reports one is the one Hyprland types with, and its
-- first keymap is the active layout.
-- `active_keymap` is the name of the layout in force ("Russian", "English (US)");
-- QS shortens it (KeyboardLayoutHypr.shortenLayout maps the same names to the
-- two-letter code the bar shows).
local SHORT = {
    ["english (us)"] = "en", ["english (uk)"] = "en-uk", ["russian"] = "ru",
    ["us"] = "en", ["us-intl"] = "en", ["us(international)"] = "en",
    ["en_us"] = "en", ["en-us"] = "en", ["ru"] = "ru", ["ru_ru"] = "ru",
    ["ru-ru"] = "ru", ["german"] = "de", ["french"] = "fr", ["finnish"] = "fi",
}

local function shorten(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end
    if SHORT[key] then return SHORT[key] end
    local inner = key:match("%(([^)]+)%)")
    if inner then
        inner = inner:lower()
        if inner == "us" or inner:sub(1, 2) == "en" then return "en" end
        if inner == "ru" or inner:sub(1, 2) == "ru" then return "ru" end
        return inner:sub(1, 2)
    end
    return key:sub(1, 3)
end

local function layout()
    run("hyprctl", { "devices", "-j" }, function(out)
        if type(out) ~= "string" then return end
        local short = shorten(out:match('"active_keymap"%s*:%s*"([^"]*)"'))
        if short then text.kb_layout = short end
    end)
end

layout()
every(2000, layout)

-- Hyprland says every layout change down its event socket (`activelayout>>device,Layout`,
-- the event HyprlandWatcherImpl reads: Services/HyprlandWatcherImpl.qml:156), so the label
-- changes on the keystroke instead of on the next poll. The two-second `hyprctl devices -j`
-- above stays as the safety net: a missed event, or the socket going away, costs a tick.
--
-- `nc -U` writes one line per event and runs until the socket closes; re-arming after a
-- second is the backoff the MPD flags plugin uses (lib/plugins/mpd/mpd.luau).
local watcher = nil
local function watch_layout()
    if watcher then return end
    local dir, sig = sys.ask("env", "XDG_RUNTIME_DIR"), sys.ask("env", "HYPRLAND_INSTANCE_SIGNATURE")
    if type(dir) ~= "string" or type(sig) ~= "string" or dir == "" or sig == "" then return end
    local ok, handle = pcall(spawn, "nc", { "-U", dir .. "/hypr/" .. sig .. "/.socket2.sock" }, function(line)
        local head, payload = tostring(line):match("^([%w_]+)>>(.*)$")
        if head ~= "activelayout" and head ~= "activelayoutv2" then return end
        local short = shorten(payload:match("^[^,]*,%s*(.+)$"))
        if short and short ~= text.kb_layout then text.kb_layout = short end
    end, function()
        watcher = nil
        after(1000, watch_layout)
    end)
    if ok then watcher = handle end
end
watch_layout()

-- ------------------------------------------------------------- system monitor
-- QS Services/SystemMonitor.qml, same probe and same arithmetic: one dash and
-- one awk over the four procfs files plus the GPU and CPU-temperature paths
-- discovered once per probe. The bar shows the same six metrics with the same
-- thresholds and the same idle rule (panel: systemMonitorHideIdle, 3%).
local SYS_PROBE = [[
tp=''
for h in /sys/class/hwmon/hwmon*/; do
  n=$(cat "$h/name" 2>/dev/null)
  case $n in k10temp|coretemp|zenpower) f="${h}temp1_input"; [ -r "$f" ] && tp=$f && break;; esac
done
[ -n "$tp" ] || tp=/sys/class/thermal/thermal_zone0/temp
gp=''; bv=0
for d in /sys/class/drm/card[0-9]*/device; do
  [ -f "$d/gpu_busy_percent" ] || continue
  v=$(cat "$d/mem_info_vram_total" 2>/dev/null) || v=0
  [ "$v" -gt "$bv" ] && bv=$v && gp=$d/gpu_busy_percent
done
awk -v tp="$tp" -v gp="$gp" '
  FILENAME=="/proc/stat"      { if (FNR==1) print "cpu", $2,$3,$4,$5,$6,$7,$8,$9; next }
  FILENAME=="/proc/meminfo"   { if ($1=="MemTotal:") t=$2; else if ($1=="MemAvailable:") a=$2; next }
  FILENAME=="/proc/swaps"     { if (FNR>1) { st+=$3; su+=$4 } next }
  FILENAME=="/proc/diskstats" { if ($3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$/) { r+=$6; w+=$10 } next }
  FILENAME==tp                { print "temp", $1+0; next }
  FILENAME==gp                { print "gpu", $1+0; next }
  END { print "mem", t+0, a+0; print "swap", st+0, su+0; print "io", r+0, w+0 }
' /proc/stat /proc/meminfo /proc/swaps /proc/diskstats "$tp" "$gp" 2>/dev/null
]]

local POLL_MS = 2000
local IO_MAX_KIBPS = 512000
local prevCpu, prevIo = nil, nil

local function clamp01(v)
    if v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function applyLine(line)
    local tag, rest = line:match("^(%a+)%s+(.*)$")
    if not tag then return end
    local n = {}
    for f in rest:gmatch("%S+") do n[#n + 1] = tonumber(f) or 0 end
    if tag == "cpu" and #n >= 8 then
        local total = 0
        for i = 1, 8 do total = total + n[i] end
        local idle = n[4] + n[5]
        if prevCpu then
            local dTotal = total - prevCpu.total
            local dIdle = idle - prevCpu.idle
            if dTotal > 0 then fact.cpu = clamp01((dTotal - dIdle) / dTotal) end
        end
        prevCpu = { total = total, idle = idle }
    elseif tag == "mem" and #n >= 2 then
        local total, avail = n[1], n[2]
        fact.ram = total > 0 and clamp01((total - avail) / total) or 0
    elseif tag == "swap" and #n >= 2 then
        local total, used = n[1], n[2]
        fact["has.swap"] = total > 0
        fact.swap = total > 0 and clamp01(used / total) or 0
    elseif tag == "io" and #n >= 2 then
        local sectors = n[1] + n[2]
        if prevIo then
            local kbps = (sectors - prevIo) / 2 / (POLL_MS / 1000)
            fact.io = clamp01(kbps / IO_MAX_KIBPS)
        end
        prevIo = sectors
    elseif tag == "temp" and #n >= 1 then
        local c = n[1] / 1000
        fact.temp = clamp01((c - 30) / 70)
    elseif tag == "gpu" and #n >= 1 then
        fact["has.gpu"] = true
        fact.gpu = clamp01(n[1] / 100)
    end
end

local function sysmon()
    run("dash", { "-c", SYS_PROBE }, function(out)
        if type(out) ~= "string" then return end
        for line in out:gmatch("[^\n]+") do applyLine(line) end
    end)
end

sysmon()
every(POLL_MS, sysmon)
