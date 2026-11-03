-- kb.luau — the keyboard chip's source, shared by the real lock and its preview.
--
-- `require("kb")(on_caps_changed)` returns a handle with `start`/`stop`: it spawns the
-- `pleamar-kbdlayout` worker (packages/pleamar-kbdlayout), subscribes to its `layout` topic, and keeps
-- two names up to date — `text.kb_layout` (the code in force, `ru`) and `fact.kb_caps`. A live
-- change of the second calls `on_caps_changed`, because the status line has three claims on it and
-- only the caller knows the other two.
--
-- Caps Lock cannot be read from a scene: the kernel keeps one LED per keyboard that has one
-- (`/sys/class/leds/*capslock*/brightness`), and the worker reads those files — the same place the
-- reference shell looked (`LockContent.qml:99-140`). A password typed in the wrong case is exactly
-- the failure a lock screen must not hide, so the sample is taken four times a second.
--
-- The switch is the compositor's, as the bar's capsule does it: `switchxkblayout current next` on
-- the device in force (`{"cmd":"switch","device":"current","direction":"next"}`).
local INTERVAL = 250

-- §7: a worker that exits is restarted after 1 s, 2 s and 5 s; after that it stays down and says
-- so, rather than being respawned forever by a scene that cannot see why it dies.
local BACKOFF_MS = { 1000, 2000, 5000 }

return function(on_caps_changed)
    local handle = nil
    local retry_timer = nil
    local retries = 0 -- restarts in a row without a sample in between
    local dead = false -- the worker speaks another version: not worth another try

    local function stop()
        if retry_timer then
            cancel(retry_timer)
            retry_timer = nil
        end
        if not handle then return end
        pcall(write, handle, '{"cmd":"stop"}\n')
        pcall(kill, handle, "term")
        handle = nil
    end

    local function line(text_line)
        local ok, v = pcall(json.decode, text_line)
        if not ok or type(v) ~= "table" then return end
        -- The handshake comes first and is the only line that carries `version` (§7): a worker of
        -- another version is killed, not talked to.
        if v.version ~= nil then
            if v.version ~= 1 then
                dead = true
                log("kb: the keyboard worker speaks version " .. tostring(v.version) .. ", not 1")
                if handle then
                    pcall(kill, handle, "term")
                    handle = nil
                end
            end
            return
        end
        if v.ok == false then
            log("kb: " .. tostring(v.err or "the keyboard worker refused a command"))
            return
        end
        if type(v.data) ~= "table" then return end
        local d = v.data
        local code = tostring(d.code or "")
        if code ~= text.kb_layout then text.kb_layout = code end
        if code ~= "" and not fact.kb_on then fact.kb_on = true end
        local caps = d.caps == true
        if caps ~= fact.kb_caps then
            fact.kb_caps = caps
            if on_caps_changed then on_caps_changed() end
        end
        retries = 0
    end

    local start

    local function on_exit(_, code)
        handle = nil
        if dead then return end
        if retries >= #BACKOFF_MS then
            if retries == #BACKOFF_MS then
                retries = retries + 1
                log("kb: the keyboard worker keeps exiting (last code " .. tostring(code) .. "); the layout chip stays stale")
            end
            return
        end
        local delay = BACKOFF_MS[retries + 1]
        retries = retries + 1
        retry_timer = after(delay, function()
            retry_timer = nil
            start()
        end)
    end

    start = function()
        if handle or dead or retry_timer then return end
        -- `spawn` with stdin open and the workers' protocol on it (INTERFACES §7): one subscription
        -- line, then samples until the `stop` courtesy line.
        local ok, id = pcall(spawn, "pleamar-kbdlayout", {}, line, on_exit, { stdin = "open" })
        if not ok or not id then
            log("kb: the keyboard worker did not start")
            return
        end
        handle = id
        write(id, '{"cmd":"subscribe","topic":"layout","interval_ms":' .. INTERVAL .. '}\n')
    end

    on("toggle_layout", function()
        if not handle then return end
        write(handle, '{"cmd":"switch","device":"current","direction":"next"}\n')
    end)

    return { start = start, stop = stop }
end
