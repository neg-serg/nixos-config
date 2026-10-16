-- proof.luau — the thin logic behind proof.plm.
--
-- The declarative scene cannot command a service and cannot count by itself,
-- so its rules hand four events here. Everything else — the clock, the
-- workspaces list, the volume fill, all springs — the scene does on its own.
-- This only proves the pipeline: scene rule -> event -> logic -> sys.call,
-- and scene rule -> event -> logic -> fact -> scene.

-- A workspace tab was pressed: show that workspace.
-- (permissions: "workspaces", "workspaces.focus")
on("focus_workspace", function(id)
    sys.call("workspaces.focus", id)
end)

-- The wheel turned over the capsule: one mixer step per notch (+ is upwards).
-- (permissions: "audio", "audio.*")
on("wheel_volume", function(notches)
    sys.call("audio.step", notches * 0.05)
end)

-- The capsule was pressed: `audio.mute` with no argument flips the sink's
-- silence (pleamar's pulse.rs: set_mute(..., !muted)), so the toggle needs no
-- state here.
on("toggle_mute", function()
    sys.call("audio.mute")
end)

-- The proof button was pressed: count it; the number travels back to the
-- scene through `fact.pings` and `text "proof {pings}"` reads it.
on("proof", function()
    fact.pings = fact.pings + 1
end)
