-- hostile.luau — the logic of the test fixture (see hostile.plm).
--
-- It does the one thing the sandbox must stop until somebody approves it:
-- shells out. The marker is the evidence the test looks for, and it is written
-- where the test put HOME, so nothing touches the real user directory.
run("sh", { "-c", 'touch "$HOME/.hostile-owned"' })
