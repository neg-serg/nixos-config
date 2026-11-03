-- voice.luau — the logic of the mpd-voice badge (see voice.plm).
--
-- The bar cannot see processes, so this polls: `pgrep -x mpd-voice` names the
-- client by its exact command (`once` is only the mode it was started with, and
-- the kernel's comm is the binary name). One second is the poll's cost and the
-- resolution the user sees; the badge is not timing-critical.
--
-- Permissions are the plugin's own: pgrep.

local POLL_MS = 1000
local timer = nil
local active = false

local function poll()
    run("pgrep", { "-x", "mpd-voice" }, function(_, code)
        if code ~= 0 and code ~= 1 then
            log("voice: pgrep exited with " .. tostring(code))
        end
        local now = (code == 0)
        if now ~= active then
            active = now
            fact.active = now
        end
        timer = after(POLL_MS, poll)
    end)
end

poll()
