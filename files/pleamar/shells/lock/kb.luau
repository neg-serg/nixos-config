-- kb.luau — the keyboard chip's source, shared by the real lock and its preview.
--
-- `require("kb")(on_caps_changed)` returns a handle with `start`/`stop`: it spawns the
-- `pleamar-kbdlayout` worker (scripts/helpers/kbd.sh), subscribes to its `layout` topic, and keeps
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

return function(on_caps_changed)
    local handle = nil

    local function stop()
        if not handle then return end
        pcall(write, handle, '{"cmd":"stop"}\n')
        pcall(kill, handle, "term")
        handle = nil
    end

    local function line(text_line)
        local ok, v = pcall(json.decode, text_line)
        if not ok or type(v) ~= "table" or type(v.data) ~= "table" then return end
        local d = v.data
        local code = tostring(d.code or "")
        if code ~= text.kb_layout then text.kb_layout = code end
        if code ~= "" and not fact.kb_on then fact.kb_on = true end
        local caps = d.caps == true
        if caps ~= fact.kb_caps then
            fact.kb_caps = caps
            if on_caps_changed then on_caps_changed() end
        end
    end

    local function start()
        if handle then return end
        -- `spawn` with stdin open and the workers' protocol on it (INTERFACES §7): one subscription
        -- line, then samples until the `stop` courtesy line.
        local ok, id = pcall(spawn, "pleamar-kbdlayout", {}, line, function() handle = nil end, { stdin = "open" })
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
