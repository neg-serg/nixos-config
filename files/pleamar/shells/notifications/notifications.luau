-- notifications.luau — the logic behind notifications.plm (PH2-C).
--
-- While this scene runs, this process IS `org.freedesktop.Notifications`, and
-- this logic is its client side:
--
--   · it watches the `notifications` service — the records the server keeps,
--     newest first — and mirrors every one into the scene's own history.json.
--     The service's `notification_history` only lives while the process does
--     (INTERFACES §6, pleamar docs B11) and holds only what expired unseen, so
--     the centre cannot lean on it: the JSON is the history.
--   · it keeps `notifications.keep(true)`: a notification centre keeps records
--     until somebody decides (the service's own advice), so a record stays
--     invocable from the centre after its toast has gone.
--   · toasts: the newest `maxToasts` records are on screen. A toast leaves the
--     stack after `autoDismissMs` (never for urgency 2) **without** being
--     dismissed — the legacy `handleDismiss` did the same, and the record
--     stays for the centre. The X and an action press DO tell the application
--     (`notifications.dismiss`), like the legacy `handleDiscard`. An arrival is
--     decided against `nt_live` (what the server keeps now), never against the
--     history: the two share id numbers across processes, and matching on them
--     cost every toast and overwrote old entries (2026-10-28).
--   · DND is the `dnd` fact (INTERFACES §2.1): while it holds, arrivals are
--     kept and listed in the centre but never toasted. Toggling the fact —
--     from the centre, from a rule or with `pleamar --say notifications "fact
--     dnd true"` — is persisted to settings.json.
--   · dismissal: `notifications.dismiss` by id, actions through
--     `notifications.invoke` (the payload the scene sends is an index into the
--     flat action table this builds on every model refresh).
--   · the centre's cursor: the legacy centre kept a `currentIndex` over its
--     list and moved it with the Emacs keys (NotificationCenter.qml:46-89). A
--     `key` rule cannot count rows, so the scene sends which key was pressed
--     (`nav`, see notifications.plm) and the cursor, its bounds and the row it
--     sits on are kept here; the scene draws the row `sel` marks and scrolls it
--     into sight.
--   · the cards' action glyphs: the legacy card picked a Material glyph for each
--     action by reading its label (NotificationCard.qml:42-62). That is a rule
--     about words, so it lives here, and the scene gets the glyph's name.
--
-- Settings (this scene's own folder, bare names; INTERFACES §6): settings.json
--   dnd           (bool,   false)           do not disturb
--   maxToasts     (number, 2, 1..6)         toasts on screen at once
--   autoDismissMs (number, 6000, 0..60000)  0 keeps a toast until it is dismissed
--   historyMax    (number, 50, 0..200)      records remembered — the ones the
--                                           server no longer keeps; the ones
--                                           still kept sit on top of those
--   sound         (bool,   false)           extra key: a short bell with a toast
-- history.json holds `items` = the records, newest first, capped by historyMax;
-- unknown keys survive in both files (reads mutate the table that was read).

local FILE = "settings.json"
local HIST = "history.json"

-- Defaults live in code; the file holds what the user changed.
local D = {
    dnd = false,
    maxToasts = 2,        -- the legacy NotificationManager.maxToastCount
    autoDismissMs = 6000, -- the QS expireTimeout fallback was 5 s; this is the schema's default
    historyMax = 50,      -- the legacy maxHistory, now persisted
    sound = false,        -- legacy played no bell; the cue is opt-in
}

local settings = {
    dnd = D.dnd,
    maxToasts = D.maxToasts,
    autoDismissMs = D.autoDismissMs,
    historyMax = D.historyMax,
    sound = D.sound,
}

-- The canonical clamp of INTERFACES §6.1: a wrong type and NaN keep the default.
local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function clean(s, def)
    if type(s) == "string" and s ~= "" then return s end
    return def
end

-- Read only: a missing file is the defaults; a broken one keeps them and says
-- so. Reads never write (INTERFACES §6.1).
local function read_file(name)
    local ok, got = pcall(function() return sys.ask("files.read", name, "json") end)
    if not ok then
        log("notifications: " .. name .. " unreadable, the defaults are used")
        return {}
    end
    if type(got) == "table" then return got end
    return {}
end

local raw = read_file(FILE)
local hist_raw = read_file(HIST)

-- ----- state -----------------------------------------------------------------

local nt_hist = {}    -- the records, newest first: { id, app, title, body, icon, image, pic, urgency, time, actions, on, slot }
-- The records the server keeps RIGHT NOW, by its own id. Not to be confused with
-- `nt_hist`: the server numbers its records from 1 in every process, so the id a
-- restored history entry carries belongs to a process that is gone. Keyed by the
-- id alone, the two collided — every record of a fresh session looked "already
-- known" because the history held a record with that number, so nothing toasted,
-- and `refresh()` overwrote the old entry with the new title and body. Measured
-- 2026-10-28: a notify-send got id 1, the toast count stayed 0 and history
-- entry 1 became the new notification. So freshness is decided here, against
-- what the server said last time, and history never enters this table.
local nt_live = {}    -- id -> record, only while the server keeps it
local nt_toast = {}   -- ids on screen, oldest first
local nt_timers = {}  -- id -> the timer that takes the toast away
local nt_acts = {}    -- flat action table, rebuilt with the models
local nt_slot = 0     -- the record handle the scene presses with
local loading = false -- while the logic itself writes `dnd`: do not save it back

local function actions_of(n)
    local out = {}
    if type(n.actions) == "table" then
        local last = math.min(#n.actions, 8)
        for i = 1, last do
            local a = n.actions[i]
            if type(a) == "table" then
                out[#out + 1] = { key = clean(a.key, ""), label = clean(a.label, "") }
            end
        end
    end
    return out
end

-- The glyph the legacy card drew before an action's label, chosen from the
-- label alone (NotificationCard.qml:42-62): the same names, in the same order,
-- with the same case-insensitive substring test, so a label that earned a glyph
-- there earns it here. "" is the reference's `return ""` — no glyph at all, and
-- the label stays centred. The names are Material Symbols ligatures, which the
-- installed Material Symbols Outlined font draws (the MPD flags do the same).
local function glyph_of(label)
    local l = string.lower(label or "")
    local function has(word) return string.find(l, word, 1, true) ~= nil end
    if has("open") then return "folder_open" end
    if has("reply") then return "reply" end
    if has("read") then return "done" end
    if has("dismiss") or has("delete") or has("clear") or has("remove") then return "delete" end
    if has("accept") or has("approve") or l == "yes" then return "check_circle" end
    if has("decline") or has("reject") or l == "no" then return "cancel" end
    if has("snooze") then return "snooze" end
    if has("mute") then return "notifications_off" end
    if has("call") then return "call" end
    if has("video") then return "videocam" end
    if has("view") then return "visibility" end
    if has("download") then return "download" end
    if has("send") then return "send" end
    if has("like") then return "thumb_up" end
    return ""
end

local function new_record(n)
    nt_slot = nt_slot + 1
    local app = clean(n.app, "Notification")
    return {
        id = n.id,
        app = app,
        title = clean(n.title, app),
        body = clean(n.body, ""),
        icon = clean(n.icon, ""),
        image = clean(n.image, ""),
        pic = clean(n.image, clean(n.icon, "")),
        urgency = num(n.urgency, 0, 2, 0),
        time = num(n.time, 0, 1e12, 0),
        actions = actions_of(n),
        on = true,
        slot = nt_slot,
    }
end

local function refresh(r, n)
    r.app = clean(n.app, r.app)
    r.title = clean(n.title, r.app)
    r.body = clean(n.body, r.body)
    r.icon = clean(n.icon, r.icon)
    r.image = clean(n.image, r.image)
    r.pic = clean(r.image, r.icon)
    r.urgency = num(n.urgency, 0, 2, r.urgency)
    r.time = num(n.time, 0, 1e12, r.time)
    r.actions = actions_of(n)
end

local function save_settings()
    raw.dnd = settings.dnd
    pcall(sys.call, "files.write", FILE, raw)
end

local function save_hist()
    local items = {}
    for i, r in ipairs(nt_hist) do
        items[i] = {
            id = r.id,
            app = r.app,
            title = r.title,
            body = r.body,
            icon = r.icon,
            image = r.image,
            urgency = r.urgency,
            time = r.time,
            actions = r.actions,
        }
    end
    hist_raw.items = items
    pcall(sys.call, "files.write", HIST, hist_raw)
end

-- ----- models ----------------------------------------------------------------

-- The body as a card can hold it: two hard lines at most, the rest said with one
-- ellipsis. The scene's `lines: 2` ends a WRAPPED line with an ellipsis, but it
-- leaves a body that carries its own newlines alone (a bot's digest, a log
-- tail), and such a body drew straight out of its card and over the row below —
-- measured 2026-10-28. The record keeps the body verbatim (history.json is the
-- history); this is the view only, so nothing is lost by shortening it.
local function view_body(s)
    if type(s) ~= "string" then return "" end
    local kept, seen = {}, 0
    for line in s:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            seen = seen + 1
            if seen <= 2 then kept[#kept + 1] = line end
        end
    end
    if seen == 0 then return "" end
    if seen > 2 then return table.concat(kept, "\n") .. " …" end
    return table.concat(kept, "\n")
end

local function entry_of(r, old, first, with_actions)
    local acts = {}
    local def = -1
    if with_actions then
        for _, a in ipairs(r.actions) do
            if a.key ~= "default" and #acts < 3 then
                nt_acts[#nt_acts + 1] = { id = r.id, key = a.key, on = r.on }
                local label = clean(a.label, a.key)
                local glyph = glyph_of(label)
                acts[#acts + 1] = {
                    ix = #nt_acts - 1,
                    label = label,
                    glyph = glyph,
                    mark = (glyph ~= "") and 1 or 0,
                }
            end
        end
        for _, a in ipairs(r.actions) do
            if a.key == "default" then
                nt_acts[#nt_acts + 1] = { id = r.id, key = "default", on = r.on }
                def = #nt_acts - 1
            end
        end
    end
    return {
        slot = r.slot,
        app = r.app,
        title = r.title,
        body = view_body(r.body),
        pic = r.pic,
        urgency = r.urgency,
        old = old,
        first = first,
        def = def,
        acts = acts,
    }
end

-- ----- the centre's window ------***--------------

-- The centre can hold 200 rows, but the scene unfolds only a window of them
-- (`model entries max 12`): the whole list stays here, every row is given its
-- place and height in design pixels, and the scene is handed the slice that
-- fits. Unfolding all of them cost the frame even with the drawer closed;
-- with the window the closed drawer carries 12 rows of static drawing and
-- nothing per frame.
local ROW_H = 96        -- a centre card's design height (see CentreCard)
local EARLIER_H = 22    -- the "Earlier" line's extra height
local GAP_H = 8         -- the list's gap, design pixels
local WINDOW = 12       -- row copies unfolded (model entries max 12)
local VIEW = 1150       -- design pixels a window must cover (4K at fit.max)

local nt_rows = {}      -- the whole centre, newest first: entries with y/h
local nt_total = 0      -- how long the whole list is, design pixels
local nt_scroll = 0     -- where the centre is scrolled, design pixels
local nt_first = 0      -- first row of the window (1-based), 0 = none
local nt_last = 0       -- last row the window holds
local nt_shown = -1     -- the window the scene was last handed (-1: nothing yet)
local nt_sel = -1       -- the cursor: a 1-based row of nt_rows, -1 = none
local nt_sel_shown = -2 -- the cursor the scene's rows were last marked with

-- The model is the window: the rows the scene draws, with `sel` on the one the
-- keyboard has (the reference's `ListView.isCurrentItem`, NotificationCenter.qml
-- :155-163). Handed over again only when the window or the cursor moved: every
-- design pixel of a scroll comes through `window_at`.
local function emit_window()
    if nt_first == nt_shown and nt_sel == nt_sel_shown then return end
    nt_shown, nt_sel_shown = nt_first, nt_sel
    local slice = {}
    for k = math.max(nt_first, 1), nt_last do
        local e = nt_rows[k]
        e.sel = (k == nt_sel) and 1 or 0
        slice[#slice + 1] = e
    end
    model.entries = slice
    fact.entryFirst = (nt_first > 0) and (nt_first - 1) or 0
    fact.entryFirstY = (nt_first > 0) and nt_rows[nt_first].y or 0
    fact.entryTotal = nt_total
end

-- Where the cursor's row sits in the whole list, and how tall it is, in design
-- pixels: the scene needs both to centre it in its own drawer, whose height only
-- that copy knows.
local function emit_cursor()
    local e = (nt_sel > 0) and nt_rows[nt_sel] or nil
    fact.selY = e and e.y or 0
    fact.selH = e and e.h or 0
end

-- `s` is where the centre is scrolled, in design pixels (`list.scroll / scale`
-- from the scene). The row that contains it starts the window; WINDOW rows
-- from there cover more than the drawer of any monitor up to 4K, and the
-- scene's `content:` is `nt_total`, so the wheel runs over the whole history.
local function window_at(s)
    nt_scroll = s
    local n = #nt_rows
    if n == 0 then
        nt_first, nt_last = 0, 0
    else
        if s < 0 then s = 0 end
        if s > nt_total then s = nt_total end
        local first = 1
        while first < n and nt_rows[first + 1].y <= s do first = first + 1 end
        if first + WINDOW - 1 > n then
            first = n - WINDOW + 1
            if first < 1 then first = 1 end
        end
        nt_first, nt_last = first, math.min(first + WINDOW - 1, n)
    end
    emit_window()
    emit_cursor()
end

local function rebuild()
    nt_acts = {}
    local toasts = {}
    for _, id in ipairs(nt_toast) do
        local r = nt_live[id]
        if r then toasts[#toasts + 1] = entry_of(r, 0, 0, true) end
    end
    model.toasts = toasts

    -- The centre: what the server still keeps (newest first), then the ones
    -- already gone, with `first` on the first of those — the "Earlier" line.
    -- The whole list lives here; only the window that fits is handed over.
    local rows = {}
    local count = 0
    for _, r in ipairs(nt_hist) do
        if r.on then
            if #rows >= 200 then break end
            rows[#rows + 1] = entry_of(r, 0, 0, true)
            count = count + 1
        end
    end
    local first_old = true
    for _, r in ipairs(nt_hist) do
        if not r.on then
            if #rows >= 200 then break end
            rows[#rows + 1] = entry_of(r, 1, first_old and 1 or 0, false)
            first_old = false
        end
    end

    -- Every row's place and height in the whole list, in design pixels: the
    -- scene multiplies them by the monitor scale (`y`/`h`, `entryFirstY`,
    -- `content: entryTotal * scale`).
    local at = 0
    for _, e in ipairs(rows) do
        e.h = ROW_H + (e.first == 1 and EARLIER_H or 0)
        e.y = at
        at = at + e.h + GAP_H
    end
    nt_rows = rows
    nt_total = (at > 0) and (at - GAP_H) or 0
    -- The cursor rides the list: a row that went away leaves it on the one that
    -- took its place, and a list that emptied has none. (The reference's
    -- `currentIndex` stays put the same way; only the moves ever set it.)
    if #nt_rows == 0 then
        nt_sel = -1
    elseif nt_sel > #nt_rows then
        nt_sel = #nt_rows
    end
    nt_shown = -1 -- the rows themselves changed: hand them over again
    window_at(nt_scroll)

    fact.count = count
end

-- ----- toasts ----------------------------------------------------------------

local function hide_toast(id)
    for i = #nt_toast, 1, -1 do
        if nt_toast[i] == id then table.remove(nt_toast, i) end
    end
    if nt_timers[id] then
        cancel(nt_timers[id])
        nt_timers[id] = nil
    end
end

-- `historyMax` caps what is REMEMBERED — the records the server no longer
-- keeps. The ones it still keeps are never dropped here: the legacy centre
-- showed every active notification and then its history on top of that.
local function trim_history()
    local kept = {}
    local old_kept = 0
    for _, r in ipairs(nt_hist) do
        if r.on or old_kept < settings.historyMax then
            kept[#kept + 1] = r
            if not r.on then old_kept = old_kept + 1 end
        else
            if nt_live[r.id] == r then nt_live[r.id] = nil end
            hide_toast(r.id)
        end
    end
    nt_hist = kept
end

-- The bell is the optional `sound` key: a short tone with the toast, a lower
-- two-tone pair for a critical one (the service itself plays nothing).
local function bell(r)
    if not settings.sound then return end
    if r.urgency >= 2 then
        sound.tone({ wave = "sine", freq = 880, to = 1320, ms = 140, volume = 0.35 })
        sound.tone({ wave = "sine", freq = 560, to = 780, ms = 180, volume = 0.22 })
    else
        sound.tone({ wave = "sine", freq = 660, to = 880, ms = 90, volume = 0.2 })
    end
end

local function arm(r)
    if nt_timers[r.id] then
        cancel(nt_timers[r.id])
        nt_timers[r.id] = nil
    end
    -- 0 means keep until dismissed; a critical one never expires on its own
    -- (the legacy expireTimer skipped urgency 2 the same way).
    if settings.autoDismissMs <= 0 or r.urgency >= 2 then return end
    local id = r.id
    nt_timers[id] = after(settings.autoDismissMs, function()
        nt_timers[id] = nil
        hide_toast(id)
        rebuild()
    end)
end

-- ----- the service -----------------------------------------------------------

local function on_notifications(list)
    if type(list) ~= "table" then return end

    local seen = {}
    local fresh = {} -- oldest first, so they toast in the order they arrived
    for i = #list, 1, -1 do
        local n = list[i]
        if type(n) == "table" and n.id ~= nil then
            seen[n.id] = true
            local r = nt_live[n.id]
            if r then
                refresh(r, n)
            else
                r = new_record(n)
                nt_live[n.id] = r
                table.insert(nt_hist, 1, r)
                fresh[#fresh + 1] = r
            end
        end
    end

    -- What the server no longer keeps is history now. Decided by identity, not
    -- by id: the ids a restored history carries belong to a process that is
    -- gone, and matching on them made every live record look like an old one.
    for id, r in pairs(nt_live) do
        if seen[id] ~= true then
            nt_live[id] = nil
            r.on = false
        end
    end
    for _, r in ipairs(nt_hist) do
        r.on = nt_live[r.id] == r
    end
    for i = #nt_toast, 1, -1 do
        local id = nt_toast[i]
        if not seen[id] then
            table.remove(nt_toast, i)
            if nt_timers[id] then
                cancel(nt_timers[id])
                nt_timers[id] = nil
            end
        end
    end

    -- A smaller historyMax is honoured live.
    trim_history()

    -- New arrivals toast unless DND holds; the stack shows the newest
    -- `maxToasts`, so the oldest one leaves the screen when one more arrives.
    for _, r in ipairs(fresh) do
        if not settings.dnd then
            if #nt_toast >= settings.maxToasts then
                local old = table.remove(nt_toast, 1)
                if nt_timers[old] then
                    cancel(nt_timers[old])
                    nt_timers[old] = nil
                end
            end
            nt_toast[#nt_toast + 1] = r.id
            bell(r)
            arm(r)
        end
    end

    save_hist()
    rebuild()
end

-- ----- what the scene sends --------------------------------------------------

-- An action (or the card's default action) was pressed: tell the application,
-- then dismiss the record like the legacy card did (invoke, then discard).
on("act", function(v)
    local ix = math.floor(num(v, -1, 1e9, -1)) + 1
    local a = nt_acts[ix]
    if a == nil or a.on ~= true then return end
    pcall(sys.call, "notifications.invoke", a.id, a.key)
    pcall(sys.call, "notifications.dismiss", a.id)
    local r = nt_live[a.id]
    if r then r.on = false end
    hide_toast(a.id)
    rebuild()
    save_hist()
end)

-- A record under the hand: one the server still keeps is dismissed (the
-- application finds out); one already gone is forgotten from the history (the
-- legacy centre's "Earlier" cards were inert; this is the port's one deviation,
-- and the only way to drop a single entry). Reached from the X of a toast, from
-- a press on a card, and from the cursor (C-k and Return).
local function drop_slot(slot)
    local r = nil
    for _, x in ipairs(nt_hist) do
        if x.slot == slot then
            r = x
            break
        end
    end
    if r == nil then return end
    if r.on then
        pcall(sys.call, "notifications.dismiss", r.id)
        r.on = false
        hide_toast(r.id)
    else
        for i = #nt_hist, 1, -1 do
            if nt_hist[i] == r then table.remove(nt_hist, i) end
        end
        if nt_live[r.id] == r then nt_live[r.id] = nil end
        hide_toast(r.id)
    end
    rebuild()
    save_hist()
end

-- A toast's dismiss mark, or a centre card, by the record's handle.
on("drop", function(v)
    drop_slot(math.floor(num(v, -1, 1e9, -1)))
end)

-- ----- the centre's cursor ---------------------------------------------------

-- The ops the scene's key rules send, in the order notifications.plm documents
-- them: one per key of the legacy list (NotificationCenter.qml:57-71, 82-89).
local NAV_NEXT, NAV_PREV = 0, 1
local NAV_FIVE_DOWN, NAV_FIVE_UP = 2, 3
local NAV_FIRST, NAV_LAST, NAV_TAKE = 4, 5, 6
-- The reference's `Math.min(idx + 5, …)`: five rows a page, not a screenful.
local PAGE = 5

-- The cursor moved. The arithmetic, the bounds and the five rows are the
-- reference's (`NotificationCenter.qml:57-62`): a cursor of -1 means nothing has
-- been chosen yet, and the first move takes the first row instead of stepping
-- off it; every move stops at an end. With nothing to move over it does nothing
-- at all (`if (notifList.count === 0) return`, :48).
--
-- The window is NOT moved here: the scene scrolls the cursor's row to the middle
-- of its drawer, as the reference did with `positionViewAtIndex(…, Center)`, and
-- the scroll coming back through `slid` moves the window under it. What leaves
-- from here is the row (`sel`, in the model) and its place (`selY`, `selH`).
local function move_cursor(op)
    local n = #nt_rows
    if n == 0 then
        nt_sel = -1
        emit_window()
        emit_cursor()
        return
    end
    local i = nt_sel
    if op == NAV_TAKE then
        -- `idx = idx < 0 ? 0 : idx` (:64): with no cursor the first row is the
        -- one that goes, and the row under it is the one the reference discards
        -- (:68) — the same thing a press on the card does in this port.
        if i < 1 then i = 1 end
        nt_sel = i
        emit_window()
        emit_cursor()
        drop_slot(nt_rows[i].slot)
        return
    elseif op == NAV_NEXT then
        i = (i < 1) and 1 or math.min(i + 1, n)
    elseif op == NAV_PREV then
        i = (i < 1) and 1 or math.max(i - 1, 1)
    elseif op == NAV_FIVE_DOWN then
        i = (i < 1) and 1 or math.min(i + PAGE, n)
    elseif op == NAV_FIVE_UP then
        i = (i < 1) and 1 or math.max(i - PAGE, 1)
    elseif op == NAV_FIRST then
        i = 1
    else -- NAV_LAST
        i = n
    end
    if i < 1 then i = 1 end
    if i > n then i = n end
    nt_sel = i
    emit_window()
    emit_cursor()
end

-- A key of the centre was pressed: `emit nav <op>` from the scene's key rules.
on("nav", function(v)
    move_cursor(math.floor(num(v, 0, 6, 0)))
end)

-- The centre scrolled: the scene sends where it is, in design pixels, and the
-- window follows. Nothing else is touched — the list runs over the whole
-- history and the rows keep their places.
on("slid", function(v)
    window_at(math.floor(num(v, 0, 1e12, 0)))
end)

-- `emit dismiss_all` — the legacy notif-close-all path (M4+space): every
-- toast leaves the stack and the centre closes, but nothing is dismissed
-- server-side, exactly like the legacy dismissAllActive().
on("dismiss_all", function()
    for _, t in pairs(nt_timers) do cancel(t) end
    nt_timers = {}
    nt_toast = {}
    fact.centre = false
    rebuild()
end)

-- `emit clear_all` — the centre's "Clear all notifications": empty the server
-- and the history (INTERFACES §8 marks the zone `agent: no`).
on("clear_all", function()
    pcall(sys.call, "notifications.clear")
    for _, t in pairs(nt_timers) do cancel(t) end
    nt_timers = {}
    nt_toast = {}
    nt_hist = {}
    nt_live = {}
    save_hist()
    rebuild()
end)

-- The `dnd` fact changed: a rule, the centre's toggle, or `--say ... fact dnd
-- true`. Persist it and, turning on, take every toast off the screen.
on("fact:dnd", function(v)
    if loading then return end
    local holds = (v == true) or (v == 1)
    if holds == settings.dnd then return end
    settings.dnd = holds
    save_settings()
    if holds then
        for _, t in pairs(nt_timers) do cancel(t) end
        nt_timers = {}
        nt_toast = {}
        rebuild()
    end
end)

-- ----- files and start -------------------------------------------------------

local function load_history()
    local items = hist_raw.items
    if type(items) ~= "table" then return end
    local last = math.min(#items, 200)
    for i = 1, last do
        local it = items[i]
        if type(it) == "table" and it.id ~= nil then
            nt_slot = nt_slot + 1
            local app = clean(it.app, "Notification")
            local r = {
                id = it.id,
                app = app,
                title = clean(it.title, app),
                body = clean(it.body, ""),
                icon = clean(it.icon, ""),
                image = clean(it.image, ""),
                pic = clean(it.image, clean(it.icon, "")),
                urgency = num(it.urgency, 0, 2, 0),
                time = num(it.time, 0, 1e12, 0),
                actions = actions_of(it),
                on = false,
                slot = nt_slot,
            }
            nt_hist[#nt_hist + 1] = r
        end
    end
end

local function apply_settings()
    raw = read_file(FILE)
    local d = raw.dnd
    if type(d) ~= "boolean" then d = D.dnd end
    settings.dnd = d
    settings.maxToasts = num(raw.maxToasts, 1, 6, D.maxToasts)
    settings.autoDismissMs = num(raw.autoDismissMs, 0, 60000, D.autoDismissMs)
    settings.historyMax = num(raw.historyMax, 0, 200, D.historyMax)
    settings.sound = (raw.sound == true)

    loading = true
    fact.dnd = settings.dnd
    loading = false

    while #nt_toast > settings.maxToasts do
        local gone = table.remove(nt_toast, 1)
        if nt_timers[gone] then
            cancel(nt_timers[gone])
            nt_timers[gone] = nil
        end
    end
    trim_history()
    rebuild()
end

load_history()
apply_settings()

-- An editor, or another copy, changed settings.json: read and clamp again.
sys.watch("files:" .. FILE, function()
    apply_settings()
end)

if sys.watch("notifications", on_notifications) then
    -- A centre keeps records until somebody decides (the docs' own reading of
    -- the standard): nothing expires on its own server-side, so a record stays
    -- invocable from the centre after its toast has gone.
    pcall(sys.call, "notifications.keep", true)
else
    log("notifications: this system has no notifications service")
end
