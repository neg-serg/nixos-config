-- voice.luau — the logic of the mpd-voice badge (see voice.plm).
--
-- The bar cannot see processes, so this polls: `pgrep -x mpd-voice` names the
-- client by its exact command (`once` is only the mode it was started with, and
-- the kernel's comm is the binary name). Two seconds is the poll's cost: the badge is not
-- timing-critical, and one second meant 60 `pgrep`s a minute.
--
-- Permissions are the plugin's own: pgrep.

local POLL_MS = 2000
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
