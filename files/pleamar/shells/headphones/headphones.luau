-- headphones.luau — the catalogue reader and EQ arithmetic of the `headphones` scene (T14).
--
-- The declarative scene draws; this file does what it cannot:
--   · list the model files in the scene's own data folder and parse them (the schema
--     camilla-model reads: name, vendor, kind, target, preamp_db, bands[], fr[][]);
--   · compute the selected model's parametric-EQ response — the RBJ cookbook biquads
--     camilla-model/src/biquad.rs implements, at 48 kHz — plus its preamp, and the measured
--     response when the file carries one, as pixel-space segments on one log grid
--     (20 Hz .. 20 kHz, 97 points): the same arithmetic as the player's pane, in Luau;
--   · keep the 8-row window under `selected` and rebuild only when it changes;
--   · run `headphones apply <file>` and put what the CLI says into `text.status`;
--   · arm the Escape latch after the surface has held the keyboard for ARM_MS.
--
-- The catalogue arrives through `headphones export --all --into <this folder>` (T12); this
-- logic only reads it, never writes. Files that are not models (no numeric `schema` or no
-- `name`) are skipped, so a `palette.json` next to the models is harmless, and a model file
-- that does not parse costs a journal line, not the list.

local VISIBLE = 8            -- rows the drawer shows; the panel is sized for exactly this many
local SAMPLE_RATE = 48000    -- the player's pane and headphones-web draw at 48 kHz
local CHART_W = 368          -- headphones.plm's plot box, design pixels
local CHART_H = 196
local DB_TOP = 12            -- the fixed window the plot draws: +12 dB at y 0, -18 at y 196
local DB_BOTTOM = -18
local POINTS = 97            -- 96 line segments, `model curve max 96` in the scene
local ARM_MS = 1500          -- launcher.luau's measured phantom-Escape delay
local STATUS_MAX = 140
local DEFAULT_FOLDER = "~/.local/share/pleamar/headphones"

local ALL = {}               -- the catalogue, sorted by vendor and name
local FOLDER = nil           -- this scene's data folder, from files.folder
local applying = false       -- a second enter while the CLI runs must not spawn twice
local arm_timer = nil

-- ======================= small helpers =======================

local function num(v)
    if type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function log10(x)
    return math.log(x) / math.log(10)
end

local function fmt_db(v)
    return string.format("%.1f", v)
end

-- The first non-empty line of what the CLI printed, short enough for the status field.
local function first_line(out)
    if type(out) ~= "string" then return "" end
    for line in string.gmatch(out, "[^\n]+") do
        line = trim(line)
        if line ~= "" then
            if #line > STATUS_MAX then line = string.sub(line, 1, STATUS_MAX - 1) .. "…" end
            return line
        end
    end
    return ""
end

local function scene_folder()
    local ok, path = pcall(function() return sys.ask("files.folder") end)
    if not ok or type(path) ~= "string" or path == "" then return nil end
    if string.sub(path, -1) == "/" then path = string.sub(path, 1, -2) end
    return path
end

-- ======================= the model files =======================

-- `Lowshelf` / `low-shelf` / `LOW_SHELF` are one shape, as in camilla-model.
local function shape_word(raw)
    if type(raw) ~= "string" then return nil end
    local word = string.lower((string.gsub(string.gsub(raw, "[%s_%-]", ""), "[^%w]", "")))
    if word == "peaking" or word == "peak" then return "peaking" end
    if word == "lowshelf" or word == "lowshelving" then return "lowshelf" end
    if word == "highshelf" or word == "highshelving" then return "highshelf" end
    if word == "lowpass" then return "lowpass" end
    if word == "highpass" then return "highpass" end
    if word == "bandpass" then return "bandpass" end
    if word == "notch" then return "notch" end
    if word == "allpass" then return "allpass" end
    return nil
end

-- One model document (a table from files.read) into the record this file works with.
local function parse_model(doc, slug)
    if type(doc) ~= "table" then return nil end
    if num(doc.schema) == nil or type(doc.name) ~= "string" or trim(doc.name) == "" then
        return nil
    end

    local bands = {}
    if type(doc.bands) == "table" then
        for _, band in ipairs(doc.bands) do
            if type(band) == "table" then
                local shape = shape_word(band.shape)
                local freq = num(band.freq)
                if shape and freq and freq > 0 then
                    local q = num(band.q)
                    if not q or q <= 0 then q = 0.7071067811865476 end
                    bands[#bands + 1] = {
                        shape = shape,
                        freq = freq,
                        gain = num(band.gain) or 0,
                        q = q,
                    }
                end
            end
        end
    end

    local fr = {}
    if type(doc.fr) == "table" then
        for _, point in ipairs(doc.fr) do
            if type(point) == "table" and num(point[1]) and num(point[2]) and point[1] > 0 then
                fr[#fr + 1] = { point[1], point[2] }
            end
        end
        table.sort(fr, function(a, b) return a[1] < b[1] end)
    end

    return {
        slug = slug,
        name = trim(doc.name),
        vendor = type(doc.vendor) == "string" and trim(doc.vendor) or "",
        kind = type(doc.kind) == "string" and trim(doc.kind) or "",
        target = type(doc.target) == "string" and trim(doc.target) or "",
        preamp = num(doc.preamp_db) or 0,
        bands = bands,
        fr = fr,
    }
end

-- ======================= the biquad response =======================
-- The same arithmetic as camilla-model/src/biquad.rs: the RBJ cookbook's coefficients,
-- normalised by a0, H(z) evaluated on the unit circle. A shape this build does not know
-- contributes nothing (the parser above already skips it).

local function coefficients(shape, freq, q, gain)
    if freq <= 0 or freq >= SAMPLE_RATE * 0.5 then return nil end
    local w0 = 2 * math.pi * freq / SAMPLE_RATE
    local cos_w0, sin_w0 = math.cos(w0), math.sin(w0)
    local alpha = sin_w0 / (2 * q)
    local a = 10 ^ (gain / 40)
    local b0, b1, b2, a0, a1, a2

    if shape == "peaking" then
        b0, b1, b2 = 1 + alpha * a, -2 * cos_w0, 1 - alpha * a
        a0, a1, a2 = 1 + alpha / a, -2 * cos_w0, 1 - alpha / a
    elseif shape == "lowshelf" or shape == "highshelf" then
        local sqrt_a = math.sqrt(a)
        local two = 2 * sqrt_a * alpha
        if shape == "lowshelf" then
            b0 = a * ((a + 1) - (a - 1) * cos_w0 + two)
            b1 = 2 * a * ((a - 1) - (a + 1) * cos_w0)
            b2 = a * ((a + 1) - (a - 1) * cos_w0 - two)
            a0 = (a + 1) + (a - 1) * cos_w0 + two
            a1 = -2 * ((a - 1) + (a + 1) * cos_w0)
            a2 = (a + 1) + (a - 1) * cos_w0 - two
        else
            b0 = a * ((a + 1) + (a - 1) * cos_w0 + two)
            b1 = -2 * a * ((a - 1) + (a + 1) * cos_w0)
            b2 = a * ((a + 1) + (a - 1) * cos_w0 - two)
            a0 = (a + 1) - (a - 1) * cos_w0 + two
            a1 = 2 * ((a - 1) - (a + 1) * cos_w0)
            a2 = (a + 1) - (a - 1) * cos_w0 - two
        end
    elseif shape == "lowpass" then
        b0, b1, b2 = (1 - cos_w0) / 2, 1 - cos_w0, (1 - cos_w0) / 2
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elseif shape == "highpass" then
        b0, b1, b2 = (1 + cos_w0) / 2, -(1 + cos_w0), (1 + cos_w0) / 2
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elseif shape == "bandpass" then
        b0, b1, b2 = alpha, 0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elseif shape == "notch" then
        b0, b1, b2 = 1, -2 * cos_w0, 1
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elseif shape == "allpass" then
        b0, b1, b2 = 1 - alpha, -2 * cos_w0, 1 + alpha
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    else
        return nil
    end

    if a0 == 0 or a0 ~= a0 then return nil end
    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 }
end

-- Its transfer function at `freq`, in dB.
local function response_db(band, freq)
    local c = coefficients(band.shape, band.freq, band.q, band.gain)
    if not c then return 0 end
    local w = 2 * math.pi * freq / SAMPLE_RATE
    local c1, s1 = math.cos(w), -math.sin(w)
    local c2, s2 = c1 * c1 - s1 * s1, 2 * c1 * s1
    local num_re = c[1] + c[2] * c1 + c[3] * c2
    local num_im = c[2] * s1 + c[3] * s2
    local den_re = 1 + c[4] * c1 + c[5] * c2
    local den_im = c[4] * s1 + c[5] * s2
    local numerator = math.sqrt(num_re * num_re + num_im * num_im)
    local denominator = math.sqrt(den_re * den_re + den_im * den_im)
    if denominator <= 0 then return 0 end
    return 20 * log10(numerator / denominator)
end

local function grid_freq(index)
    return 20 * (1000 ^ (index / (POINTS - 1)))
end

-- The EQ's own response: every band's curve summed with the preamp, which is a Gain filter
-- that also runs.
local function eq_values(model)
    local out = {}
    for i = 0, POINTS - 1 do
        local freq = grid_freq(i)
        local sum = model.preamp
        for _, band in ipairs(model.bands) do
            sum = sum + response_db(band, freq)
        end
        out[i + 1] = sum
    end
    return out
end

-- The measured response held at the ends and straight-line in between on a log frequency
-- axis (camilla-model's `fr_curve`), or nil when the file has no measurement.
local function measured_values(model)
    local points = model.fr
    if #points == 0 then return nil end
    local first, last = points[1], points[#points]
    local out = {}
    for i = 0, POINTS - 1 do
        local freq = grid_freq(i)
        if freq <= first[1] then
            out[i + 1] = first[2]
        elseif freq >= last[1] then
            out[i + 1] = last[2]
        else
            local lo, hi = 1, #points
            while hi - lo > 1 do
                local mid = math.floor((lo + hi) / 2)
                if points[mid][1] <= freq then lo = mid else hi = mid end
            end
            local f0, db0 = points[lo][1], points[lo][2]
            local f1, db1 = points[hi][1], points[hi][2]
            local t = (math.log(freq) - math.log(f0)) / (math.log(f1) - math.log(f0))
            out[i + 1] = db0 + (db1 - db0) * t
        end
    end
    return out
end

-- dB values into the plot's own pixels: x along the log grid, y through the fixed window,
-- clamped so a curve that leaves the window runs along the edge.
local function segments(values)
    local out = {}
    local prev_x, prev_y = nil, nil
    for i = 1, #values do
        local x = (i - 1) / (POINTS - 1) * CHART_W
        local y = (DB_TOP - values[i]) / (DB_TOP - DB_BOTTOM) * CHART_H
        if y < 0 then y = 0 elseif y > CHART_H then y = CHART_H end
        if prev_x then
            out[#out + 1] = { x1 = prev_x, y1 = prev_y, x2 = x, y2 = y }
        end
        prev_x, prev_y = x, y
    end
    return out
end

-- ======================= the visible slice and the curves =======================

local function read_models()
    local models = {}
    local ok, names = pcall(function() return sys.ask("files.list") end)
    if not ok or type(names) ~= "table" then
        log("headphones: cannot list the catalogue folder: " .. tostring(names))
        return models
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and string.sub(name, -5) == ".json" then
            local slug = string.sub(name, 1, -6)
            local ok_read, doc = pcall(function() return sys.ask("files.read", name, "json") end)
            if ok_read then
                local parsed = parse_model(doc, slug)
                if parsed then
                    models[#models + 1] = parsed
                end
            else
                log("headphones: " .. name .. " is not a model file: " .. tostring(doc))
            end
        end
    end
    table.sort(models, function(a, b)
        local av, bv = string.lower(a.vendor), string.lower(b.vendor)
        if av ~= bv then return av < bv end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return models
end

local function selected_model()
    local index = math.floor(fact.selected) + 1
    return ALL[index]
end

local function rebuild_rows()
    local total = #ALL
    local selected = clamp(math.floor(fact.selected), 0, math.max(0, total - 1))
    local offset = clamp(math.floor(fact.offset), 0, math.max(0, total - VISIBLE))
    if selected < offset then offset = selected end
    if selected >= offset + VISIBLE then offset = selected - VISIBLE + 1 end
    offset = clamp(offset, 0, math.max(0, total - VISIBLE))
    if fact.offset ~= offset then fact.offset = offset end

    local rows = {}
    for index = offset, math.min(total, offset + VISIBLE) - 1 do
        local m = ALL[index + 1]
        local sub = m.vendor
        if m.kind ~= "" then
            if sub ~= "" then sub = sub .. " · " end
            sub = sub .. m.kind
        end
        rows[#rows + 1] = { idx = index, title = m.name, sub = sub }
    end
    model.rows = rows
    if total == 0 then
        text.counter = "каталог пуст"
    else
        text.counter = tostring(selected + 1) .. " / " .. tostring(total)
    end
end

local function rebuild_curve()
    local m = selected_model()
    if not m then
        model.curve = {}
        model.measured = {}
        text.model_name = "нет модели"
        text.model_meta = ""
        text.model_facts = ""
        return
    end

    model.curve = segments(eq_values(m))
    local measured = measured_values(m)
    model.measured = measured and segments(measured) or {}

    text.model_name = m.name
    local meta = m.vendor
    if m.kind ~= "" then
        if meta ~= "" then meta = meta .. " · " end
        meta = meta .. m.kind
    end
    if m.target ~= "" then
        if meta ~= "" then meta = meta .. " · " end
        meta = meta .. m.target
    end
    text.model_meta = meta
    local facts = "preamp " .. fmt_db(m.preamp) .. " дБ · полос: " .. tostring(#m.bands)
    if #m.fr > 0 then
        facts = facts .. " · замер: " .. tostring(#m.fr) .. " точек"
    end
    text.model_facts = facts
end

local function read_catalog()
    FOLDER = scene_folder()
    local previous = selected_model()
    local previous_slug = previous and previous.slug or nil
    ALL = read_models()

    local index = 0
    if previous_slug then
        for i, m in ipairs(ALL) do
            if m.slug == previous_slug then
                index = i - 1
                break
            end
        end
    end
    fact.total = #ALL
    fact.selected = clamp(index, 0, math.max(0, #ALL - 1))
    fact.offset = clamp(math.floor(fact.offset), 0, math.max(0, #ALL - VISIBLE))

    if #ALL == 0 then
        text.empty_hint = "headphones export --all --into " .. (FOLDER or DEFAULT_FOLDER)
    end
    rebuild_rows()
    rebuild_curve()
end

-- ======================= the Escape latch =======================

local function disarm()
    fact.armed = false
    if arm_timer then
        cancel(arm_timer)
        arm_timer = nil
    end
end

-- ======================= events =======================

-- Opening or closing by any route (the chord's `toggle_drawer`, `fact open …`, the catcher,
-- Escape) ends here: the folder is re-read on every open, so a fresh export shows without `r`,
-- and the latch is armed one phantom-Escape late (see launcher.plm's note).
on("fact:open", function(open)
    disarm()
    if open then
        text.status = ""
        read_catalog()
        arm_timer = after(ARM_MS, function()
            arm_timer = nil
            fact.armed = true
        end)
    else
        text.status = ""
    end
end)

-- The scene rule moved the selection: re-window the list and redraw the curve. The logic's own
-- `read_catalog` also passes through here; neither sets `selected`, so there is no loop.
on("fact:selected", function()
    if not fact.open then return end
    rebuild_rows()
    rebuild_curve()
end)

on("reload_catalog", function()
    read_catalog()
    text.status = "прочитано моделей: " .. tostring(#ALL)
end)

-- `enter`: apply the model the drawer is showing, by the file it was read from. A bare slug
-- would make the CLI look in its own model and catalog directories, where a catalogue model
-- this drawer lists need not have a copy.
on("apply_model", function()
    if applying then return end
    local m = selected_model()
    if not m then
        text.status = "нечего применять: каталог пуст"
        return
    end
    local path = m.slug .. ".json"
    if FOLDER then path = FOLDER .. "/" .. path end

    applying = true
    text.status = "применяю " .. m.name .. "…"
    local ok, err = pcall(function()
        run("headphones", { "apply", path }, function(out, code)
            applying = false
            local line = first_line(out)
            if code == 0 then
                text.status = line ~= "" and line or ("применено: " .. m.slug)
            else
                if line == "" then line = "код " .. tostring(code) end
                text.status = "не применено: " .. line
            end
        end, { errors = true })
    end)
    if not ok then
        applying = false
        text.status = "не применено: " .. tostring(err)
    end
end)

-- ======================= start-up =======================
-- The scene is born closed; reading once here means the first open is already populated and
-- the keeper never has to wait for a disk walk.

read_catalog()
