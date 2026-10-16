-- overlay.luau — the logic of the overlay scene (PH2-D).
--
-- What a rule cannot do: watch the two cache semaphores (they live outside the
-- scene's own folder, so `run("stat", …)` watches them — permission `run:
-- "stat"`), relay a dismissal to the scenes that own overlays with
-- `pleamar --say`, and hold the idle inhibitor open with `systemd-inhibit`.
--
-- The semaphores are the legacy `~/.cache/quickshell/{dismiss-overlay,
-- notif-close-all}` under the pleamar cache (INTERFACES §1.2). This scene owns
-- them: at startup it makes `$XDG_CACHE_HOME/pleamar/` and touches both, so a
-- compositor bind's plain `touch` works; a change of mtime is the signal. The
-- first observation of each file is only a baseline, so a leftover file does
-- not dismiss anything when the scene starts.
--
-- Broadcasting: the port has one scene per overlay, so the legacy "dismiss the
-- one active overlay" is a relay to the scenes that own one. `dismiss` (the
-- catcher's press, Escape, `pleamar --say overlay "emit dismiss"`, or the
-- dismiss-overlay semaphore) closes a drawer, the notification centre and the
-- toasts; `notif-close-all` (the legacy M4+space) closes notifications and the
-- screenshot toast only. A scene that is not running answers nothing; the
-- relay does not wait for it.

local FILE = "settings.json"

-- Settings (INTERFACES §6.3, defaults and clamps here; unknown keys survive).
local raw = {}
local function read_file()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then return got end
    return {}
end

local function apply()
    -- A wrong type keeps the default; only an explicit `false` turns it off.
    fact.dismiss_on_escape = (raw.dismissOnEscape ~= false)
end

raw = read_file()
apply()

-- An editor, or a later settings UI, changed the file: honoured live.
sys.watch("files:" .. FILE, function()
    raw = read_file()
    apply()
end)

-- ------***------------------------- the semaphores
local HOME = "/tmp"
local CACHE = "/tmp/.cache"

local ok_home, home = pcall(function() return sys.ask("env", "HOME") end)
if ok_home and type(home) == "string" and home ~= "" then HOME = home end

local ok_cache, cache = pcall(function() return sys.ask("env", "XDG_CACHE_HOME") end)
if ok_cache and type(cache) == "string" and cache ~= "" then CACHE = cache end

local DIR = CACHE .. "/pleamar"
local DISMISS = DIR .. "/dismiss-overlay"
local NOTIF = DIR .. "/notif-close-all"

-- ------***------------------------- the relay
-- One `pleamar --say <scene> <commands…>` per scene. A scene that is not
-- running (or is still starting) prints its own error and exits non-zero; the
-- relay ignores it, because the rest of the dismissal still has to happen.
local function say(scene, ...)
    local args = { "--say", scene }
    for _, a in ipairs({ ... }) do args[#args + 1] = a end
    run("pleamar", args)
end

local function dismiss_all()
    fact.active = false
    say("panels", "fact", "drawer", "none")
    say("notifications", "emit", "dismiss_all")
    say("launcher", "fact", "open", "false")
    say("toast", "emit", "hide")
end

local function close_all_notifications()
    fact.active = false
    say("notifications", "emit", "dismiss_all")
    say("toast", "emit", "hide")
end

on("dismiss", function()
    dismiss_all()
end)

-- ------***--------------------- watching a file
local POLL_MS = 600

-- `stat -c %y` says the file is there and when it changed; the string is the
-- whole comparison. The first observation is the baseline; a file that is gone
-- changes nothing (there is nothing to dismiss), and one that appears fires.
local function watch(path, fire)
    local last = nil
    every(POLL_MS, function()
        run("stat", { "-c", "%y", path }, function(out, code)
            local now = ""
            if code == 0 and type(out) == "string" then now = out end
            if last == nil then
                last = now
                return
            end
            if now ~= "" and now ~= last then
                last = now
                fire()
            end
        end)
    end)
end

local started = false
local function start_watching()
    if started then return end
    started = true
    watch(DISMISS, dismiss_all)
    watch(NOTIF, close_all_notifications)
end

-- Own the files, then watch them: `touch` never fails on a bind, and the
-- baseline is taken after the touch, so creating them fires nothing. The
-- fallback starts the watching anyway if a `run` never answers.
run("mkdir", { "-p", DIR }, function()
    run("touch", { DISMISS }, function()
        run("touch", { NOTIF }, function()
            start_watching()
        end)
    end)
end)
after(5000, start_watching)

-- ------***--------------------- the idle inhibitor
-- `systemd-inhibit … sleep infinity` holds logind's idle/sleep inhibitor for
-- as long as it runs (the legacy IdleInhibitor.qml). It is spawned only while
-- `inhibit` is true; a failure (or a `systemd-inhibit` that was killed from
-- outside) surfaces in `inhibit_error` and the fact stays as it is, so the
-- next raise tries again. On scene shutdown the platform kills it.
local inh = nil

local function inhibit_apply()
    if fact.inhibit and not inh then
        fact.inhibit_error = ""
        -- A missing program must not take the fact handler down with it.
        local ok = pcall(function()
            inh = spawn(
                "systemd-inhibit",
                { "--what=idle:sleep", "--who=pleamar", "--why=User requested", "sleep", "infinity" },
                function(_) end,
                function(_, code)
                    inh = nil
                    if fact.inhibit then
                        fact.inhibit_error = "systemd-inhibit exited with " .. tostring(code)
                        log("idle inhibitor: systemd-inhibit exited with", code)
                    end
                end
            )
        end)
        if not ok or inh == nil then
            inh = nil
            fact.inhibit_error = "systemd-inhibit could not start"
            log("idle inhibitor: systemd-inhibit could not start")
        end
    elseif not fact.inhibit and inh then
        kill(inh, "term")
        inh = nil
    end
end

-- `fact inhibit true|false` (IPC) and `emit toggle_inhibit` (IPC/bind) are the
-- two roads in; both end in `inhibit_apply`.
on("fact:inhibit", inhibit_apply)
on("toggle_inhibit", function()
    fact.inhibit = not fact.inhibit
    inhibit_apply()
end)
