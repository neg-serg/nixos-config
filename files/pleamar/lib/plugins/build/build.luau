-- build.luau — the logic of the build badge (see build.plm).
--
-- Legacy: files/quickshell/Bar/Modules/BuildStatus.qml. QS ran the same tool with
-- `--watch 1 --json` and kept `stateClass`/`statusText`/`statusTooltip`/`builds`;
-- here one JSON object per line arrives from `spawn` and lands in the scene's
-- facts and texts.
--
-- What the port decides on its own is the *word* beside the glyph. The tool's
-- `text` carries a nerd-font icon of its own ("` building probe-build-status +1
-- 6s`"), which would be a second icon next to the tile's Material one, so the
-- summary is built from the same numbers: the first build's derivation, and
-- "+N" for the ones behind it.
--
-- Idle is the state the badge hides in: `count == 0` or `class == "idle"`.
--
-- Permissions are the plugin's own: nixbuild-status.

local GLYPH = {
    idle = "check_circle",
    evaluating = "search",
    building = "build",
    activating = "bolt",
}

-- The tile's tone by phase: the two that are work-in-progress read in the accent,
-- the one that touches the system (activation) in the warning colour.
local TONE = {
    idle = 0,
    evaluating = 1,
    building = 1,
    activating = 2,
}

local id = nil
local restarts = 0

-- The first build's name, from the fields the tool documents (`drvs` is its own
-- list of derivations; `head` is the command line when it named no derivation).
local function nameOf(build)
    if type(build) ~= "table" then return "" end
    local drvs = build.drvs
    if type(drvs) == "table" and type(drvs[1]) == "string" then return drvs[1] end
    if type(build.head) == "string" then return build.head end
    return ""
end

local function idle()
    fact.busy = false
    fact.count = 0
    model.builds = {}
    text.stage = "idle"
    text.glyph = GLYPH.idle
    fact.tone = 0
    text.summary = ""
end

-- The tool prints its own summary in `text` ("<icon> building probe-drawer +2 17s") and
-- names the build better than its own `drvs` list does — the first entry there is whatever
-- is being compiled at that instant, not what the reader asked for. So the word beside the
-- glyph is the tool's: the nerd-font icon and the phase word come off, the rest stays.
local function summaryOf(value, class)
    local text = tostring(value or "")
    text = text:gsub("^[^%w]+", "")
    if class ~= "" then
        text = text:gsub("^" .. class .. "%s+", "")
    end
    -- The clock at the end ("9s") moves every second: the badge is a caption, not a
    -- stopwatch, and a width that changes once a second is a bar that jitters. The popup
    -- has the row's own elapsed for that.
    text = text:gsub("%s+%d+[smhd]%s*$", "")
    return (text:gsub("%s+$", ""))
end

local function apply(line)
    if type(line) ~= "string" or line == "" then return end
    local ok, state = pcall(function() return json.decode(line) end)
    if not ok or type(state) ~= "table" then
        log("build: a line that is not one JSON object: " .. tostring(line))
        return
    end
    local class = tostring(state.class or "idle")
    local count = tonumber(state.count) or 0
    text.stage = class
    text.glyph = GLYPH[class] or "build"
    fact.tone = TONE[class] or 0
    text.detail = tostring(state.tooltip or "")
    fact.count = count
    fact.busy = count > 0 and class ~= "idle"
    if not fact.busy then
        text.summary = ""
        model.builds = {}
        return
    end
    local builds = state.builds
    -- The popup's list, in the tool's own order, capped at the model's 8.
    local rows = {}
    if type(builds) == "table" then
        for i = 1, math.min(#builds, 8) do
            local b = builds[i]
            if type(b) == "table" then
                rows[#rows + 1] = {
                    name = nameOf(b),
                    stage = tostring(b.phase or class),
                    elapsed = tostring(b.elapsed_text or ""),
                }
            end
        end
    end
    model.builds = rows
    local first = type(builds) == "table" and builds[1] or nil
    local name = summaryOf(state.text, class)
    if name == "" then name = nameOf(first) end
    if name == "" then name = class end
    text.summary = name
end

local function start()
    -- Three seconds, not one: nixbuild-status scans /proc and the derivation log on every tick, and
    -- the badge cost 0.40 % of a core at 1 s (measured 2026-11-08). A build state that updates
    -- within 3 s is enough for a capsule that changes on the scale of minutes.
    id = spawn("nixbuild-status", { "--format", "waybar", "--watch", "3" }, apply, function(_, code)
        id = nil
        -- The tool exits when it cannot read /proc or the derivation log; the badge
        -- then has nothing to say and must not keep claiming a build.
        idle()
        restarts = restarts + 1
        if restarts <= 3 then
            after(({ 1000, 2000, 5000 })[restarts], start)
        else
            log("build: nixbuild-status keeps failing (last exit " .. tostring(code) .. "); staying idle")
        end
    end)
end

-- One worker for the life of the logic: the platform stops what the logic started
-- on a reload and on scene exit (INTERFACES §7), so there is no teardown to write.
start()
