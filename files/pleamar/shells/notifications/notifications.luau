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
--     (`notifications.dismiss`), like the legacy `handleDiscard`.
--   · DND is the `dnd` fact (INTERFACES §2.1): while it holds, arrivals are
--     kept and listed in the centre but never toasted. Toggling the fact —
--     from the centre, from a rule or with `pleamar --say notifications "fact
--     dnd true"` — is persisted to settings.json.
--   · dismissal: `notifications.dismiss` by id, actions through
--     `notifications.invoke` (the payload the scene sends is an index into the
--     flat action table this builds on every model refresh).
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
local nt_known = {}   -- id -> record
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

local function entry_of(r, old, first, with_actions)
    local acts = {}
    local def = -1
    if with_actions then
        for _, a in ipairs(r.actions) do
            if a.key ~= "default" and #acts < 3 then
                nt_acts[#nt_acts + 1] = { id = r.id, key = a.key, on = r.on }
                acts[#acts + 1] = { ix = #nt_acts - 1, label = clean(a.label, a.key) }
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
        body = r.body,
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
local nt_win = 0        -- first row of the window (1-based), 0 = none
local nt_win_n = 0      -- how many rows the window holds

-- `s` is where the centre is scrolled, in design pixels (`list.scroll / scale`
-- from the scene). The row that contains it starts the window; WINDOW rows
-- from there cover more than the drawer of any monitor up to 4K, and the
-- scene's `content:` is `nt_total`, so the wheel runs over the whole history.
local function window_at(s)
    nt_scroll = s
    local n = #nt_rows
    if n == 0 then
        nt_win, nt_win_n = 0, 0
        model.entries = {}
        fact.entryFirst = 0
        fact.entryFirstY = 0
        fact.entryTotal = 0
        return
    end
    if s < 0 then s = 0 end
    if s > nt_total then s = nt_total end
    local first = 1
    while first < n and nt_rows[first + 1].y <= s do first = first + 1 end
    local last = first + WINDOW - 1
    if last > n then
        last = n
        first = last - WINDOW + 1
        if first < 1 then first = 1 end
    end
    if nt_win_n > 0 and first == nt_win then return end
    local slice = {}
    for k = first, last do slice[#slice + 1] = nt_rows[k] end
    nt_win, nt_win_n = first, #slice
    fact.entryFirst = first - 1
    fact.entryFirstY = nt_rows[first].y
    fact.entryTotal = nt_total
    model.entries = slice
end

local function rebuild()
    nt_acts = {}
    local toasts = {}
    for _, id in ipairs(nt_toast) do
        local r = nt_known[id]
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
    nt_win, nt_win_n = 0, 0
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
            nt_known[r.id] = nil
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
            local r = nt_known[n.id]
            if r then
                refresh(r, n)
            else
                r = new_record(n)
                nt_known[n.id] = r
                table.insert(nt_hist, 1, r)
                fresh[#fresh + 1] = r
            end
        end
    end

    -- What the server no longer keeps is history now.
    for _, r in ipairs(nt_hist) do
        r.on = seen[r.id] == true
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
    local r = nt_known[a.id]
    if r then r.on = false end
    hide_toast(a.id)
    rebuild()
    save_hist()
end)

-- A toast's dismiss mark, or a centre card: a record the server still keeps is
-- dismissed (the application finds out); one already gone is forgotten from
-- the history (the legacy centre's "Earlier" cards were inert; this is the
-- port's one deviation, and the only way to drop a single entry).
on("drop", function(v)
    local slot = math.floor(num(v, -1, 1e9, -1))
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
        nt_known[r.id] = nil
        hide_toast(r.id)
    end
    rebuild()
    save_hist()
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
    nt_known = {}
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
            nt_known[r.id] = r
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
