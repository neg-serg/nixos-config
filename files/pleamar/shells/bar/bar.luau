-- bar.luau — the thin logic behind bar.plm.
--
-- The declarative scene draws, animates and reads its services on its own; only
-- what no rule can do is here: command the services, and merge the bar's few
-- settings from the scene's own folder. Nothing here paints or knows coordinates.

local FILE = "settings.json"

-- Defaults in code, clamps too; a file under the scene's folder
-- (~/.local/share/pleamar/bar/settings.json) overrides them.
local DEFAULT = { side_margin = 4, volume_step = 0.05 }

local volume_step = DEFAULT.volume_step

-- Read and merge only. `pcall` because `files.read` raises on a file that is not
-- valid JSON; a missing file, a broken one or a key of the wrong type all fall
-- back to the default. Returns the merged values plus what the file gave, so the
-- caller can tell whether it needs writing back.
local function merge()
    local ok, saved = pcall(sys.ask, "files.read", FILE, "json")
    if not ok or type(saved) ~= "table" then saved = {} end
    local side = tonumber(saved.side_margin) or DEFAULT.side_margin
    local step = tonumber(saved.volume_step) or DEFAULT.volume_step
    return {
        side_margin = math.max(0, math.min(16, side)),      -- design px, nothing outside 0..16
        volume_step = math.max(0.01, math.min(0.25, step)), -- one wheel notch, 1%..25%
        given = saved,
    }
end

local function apply(settings)
    fact.side = settings.side_margin
    volume_step = settings.volume_step
end

local settings = merge()
apply(settings)

-- Write the merged settings back when the file was missing or incomplete: the
-- first run leaves a file to edit, and from then on the file is the source of
-- truth. A settings UI (a later slice) writes here again on every change; this
-- slice has nothing the user can change at runtime yet.
if type(settings.given.side_margin) ~= "number" or type(settings.given.volume_step) ~= "number" then
    sys.call("files.write", FILE, { side_margin = settings.side_margin, volume_step = settings.volume_step })
end

-- Somebody edited the file — an editor, or another copy of the scene: take the
-- new values, clamped the same way.
sys.watch("files:" .. FILE, function()
    apply(merge())
end)

-- ---------------------------------------------------------------- commands
-- A workspace tab was pressed: show that workspace.
-- (permissions: "workspaces", "workspaces.focus")
on("focus_workspace", function(id)
    sys.call("workspaces.focus", id)
end)

-- The wheel turned over the volume capsule: one settings step per notch
-- (+ is upwards). (permissions: "audio", "audio.*")
on("wheel_volume", function(notches)
    sys.call("audio.step", notches * volume_step)
end)

-- The capsule was pressed: `audio.mute` with no argument flips the sink's
-- silence (pleamar's pulse.rs: set_mute(..., !muted)), so the toggle needs no
-- state here. (permissions: "audio", "audio.*")
on("toggle_mute", function()
    sys.call("audio.mute")
end)
