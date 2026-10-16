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
local WIDGETS = { "clock", "workspaces", "network", "volume" }

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
