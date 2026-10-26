-- pill.luau — the logic of the pill tracker plugin (see pill.plm).
--
-- Legacy: files/quickshell/Services/PillTracker.qml + Helpers/PillHistory.js.
-- Same behaviour, same shapes:
--
--   - one JSON state — today's date, whether it is taken and at what time, and
--     the history of the days before (newest first) — rolled over at midnight,
--     and reconciled at start with the calendar events, which are the record
--     that outlived the cutover from Quickshell (see `syncFromCalendar`);
--   - taking it writes an all-day VEVENT into the synced calendar
--     (`<HOME>/.config/vdirsyncer/calendars/pills/pill-<date>.ics`), untaking it
--     removes that file;
--   - `reminder` is true once the deadline (`Pill.deadline`, the QS
--     `pillReminderDeadline` default 12:00) has passed with nothing taken;
--   - `streak` is the QS `calculateStreak`: today counted only when taken, then
--     the run of taken days immediately before it (a gap ends it).
--
-- Permissions are the plugin's own: mkdir, tee, rm, ls; files (its own folder),
-- env (HOME), clock (the minute).

local STATE = "state.json"
local CAL_SUBDIR = "/.config/vdirsyncer/calendars/pills/"

local today = ""
local taken = false
local takenAt = ""
local history = {}      -- newest first: { date = "YYYY-MM-DD", taken = bool, takenAt = "HH:MM" }
local lastClock = nil   -- the last minute the clock reported

local function pad2(n)
    return string.format("%02d", n or 0)
end

local function dateStr(clock)
    return string.format("%04d-%02d-%02d", clock.year or 1970, clock.month or 1, clock.day or 1)
end

local function timeStr(clock)
    return pad2(clock.hour) .. ":" .. pad2(clock.minute)
end

local function leap(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local function daysInMonth(year, month)
    local lengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and leap(year) then return 29 end
    return lengths[month] or 30
end

-- The QS prevDay: one day back, in the same "YYYY-MM-DD" shape.
local function prevDay(date)
    local year, month, day = date:match("(%d+)-(%d+)-(%d+)")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year then return nil end
    if day > 1 then
        day = day - 1
    elseif month > 1 then
        month = month - 1
        day = daysInMonth(year, month)
    else
        year = year - 1
        month = 12
        day = 31
    end
    return string.format("%04d-%02d-%02d", year, month, day)
end

local function calDir()
    local home = sys.ask("env", "HOME")
    if type(home) ~= "string" or home == "" then home = "/home/neg" end
    return home .. CAL_SUBDIR
end

local function icsPath()
    return calDir() .. "pill-" .. today .. ".ics"
end

local function icsText()
    local stamp = today:gsub("%-", "")
    return table.concat({
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Neg//PillTracker//EN",
        "BEGIN:VEVENT",
        "DTSTART;VALUE=DATE:" .. stamp,
        "DTEND;VALUE=DATE:" .. stamp,
        "SUMMARY:Pill ✅",
        "DESCRIPTION:Taken at " .. takenAt,
        "CATEGORIES:Health",
        "END:VEVENT",
        "END:VCALENDAR",
        "",
    }, "\r\n")
end

-- The state file is the plugin's own, so the files service writes it (a table
-- goes out as JSON); the calendar event lives outside that folder and goes
-- through `tee`, the way the QS heredoc did.
local function persist()
    local state = { today = today, taken = taken, takenAt = takenAt, history = history }
    local ok, err = pcall(sys.call, "files.write", STATE, state)
    if not ok then log("pill: state not saved: " .. tostring(err)) end
end

local function writeEvent()
    local ok, err = pcall(run, "tee", { icsPath() }, nil, { input = icsText(), output = false })
    if not ok then log("pill: calendar event not written: " .. tostring(err)) end
end

local function removeEvent()
    pcall(run, "rm", { "-f", icsPath() })
end

local function streakNow()
    if not taken then return 0 end
    local count = 1
    local cursor = today
    local seenToday = false
    for _, entry in ipairs(history) do
        if type(entry) ~= "table" then break end
        -- An entry dated today is the state above, not the day before it: step over it once.
        if entry.date == today and not seenToday then
            seenToday = true
        elseif entry.taken ~= true then
            break
        else
            local expected = prevDay(cursor)
            if not expected or entry.date ~= expected then break end
            count = count + 1
            cursor = entry.date
        end
    end
    return count
end

local function publish()
    fact.taken = taken
    text.takenAt = takenAt
    text.today = today
    fact.streak = streakNow()
end

-- The calendar is the record that outlived the cutover: Quickshell wrote a
-- `pill-<date>.ics` there on every take and this plugin writes the same file, so
-- the days before the port existed are on disk even though `state.json` is
-- younger than them. Listing the directory gives the streak its history instead
-- of restarting at zero on the day the port took over — the QS service's own
-- `_syncFromCalendar` did the same.
local HISTORY_MAX = 400

local function syncFromCalendar()
    local ok = pcall(run, "ls", { "-1", calDir() }, function(out)
        if type(out) ~= "string" then return end
        local onDisk = {}
        for name in out:gmatch("[^\r\n]+") do
            local date = name:match("^pill%-(%d%d%d%d%-%d%d%-%d%d)%.ics$")
            if date then onDisk[date] = true end
        end
        -- Today is the state above (`taken`/`takenAt`), never a history entry: a file dated today
        -- means the pill is taken today, and an entry for it would eat the streak — `streakNow` walks
        -- back from yesterday and would find today where it expects yesterday. An older state file
        -- may carry such an entry (this sync wrote one before it knew better), so it is dropped.
        local merged, known = {}, {}
        for _, entry in ipairs(history) do
            if type(entry) == "table" and type(entry.date) == "string" and entry.date ~= today then
                known[entry.date] = true
                -- A file on disk means the day was taken, whatever the state says.
                if onDisk[entry.date] then entry.taken = true end
                merged[#merged + 1] = entry
            end
        end
        for date in pairs(onDisk) do
            if date == today then
                if not taken then taken = true end
            elseif not known[date] then
                merged[#merged + 1] = { date = date, taken = true, takenAt = "" }
            end
        end
        table.sort(merged, function(a, b) return a.date > b.date end)
        while #merged > HISTORY_MAX do table.remove(merged) end
        history = merged
        persist()
        publish()
    end)
    if not ok then log("pill: the calendar could not be listed") end
end

local function deadlinePassed()
    if not lastClock then return false end
    local hour = fact.deadlineHour or 12
    local minute = fact.deadlineMinute or 0
    local now = (lastClock.hour or 0) * 60 + (lastClock.minute or 0)
    return now >= hour * 60 + minute
end

local function refreshReminder()
    local reminder = (not taken) and deadlinePassed()
    if reminder ~= fact.reminder then fact.reminder = reminder end
end

-- Midnight: the day that just ended is archived whether it was taken or not,
-- because the streak needs the misses too (the QS `_checkDate`).
local function rollover()
    if today ~= "" then
        table.insert(history, 1, { date = today, taken = taken, takenAt = takenAt })
    end
    taken = false
    takenAt = ""
    fact.reminder = false
end

local function onClock(clock)
    if type(clock) ~= "table" then return end
    lastClock = clock
    local date = dateStr(clock)
    if today == "" then
        today = date
        publish()
        refreshReminder()
        return
    end
    if date ~= today then
        rollover()
        today = date
        persist()
        publish()
    end
    refreshReminder()
end

-- ------------------------------------------------------------------ state
local function load()
    local ok, state = pcall(sys.ask, "files.read", STATE, "json")
    if not ok or type(state) ~= "table" then return end
    today = type(state.today) == "string" and state.today or ""
    taken = state.taken == true
    takenAt = type(state.takenAt) == "string" and state.takenAt or ""
    history = type(state.history) == "table" and state.history or {}
end

-- ---------------------------------------------------------------- gestures
on("toggle", function()
    if today == "" then return end -- the clock has not reported yet
    if taken then
        taken = false
        takenAt = ""
        removeEvent()
    else
        taken = true
        takenAt = lastClock and timeStr(lastClock) or ""
        writeEvent()
    end
    persist()
    publish()
    fact.reminder = false
end)

pcall(run, "mkdir", { "-p", calDir() })
load()
publish()
syncFromCalendar()
sys.watch("clock", onClock)
