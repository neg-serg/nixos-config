-- Smart TidalCycles actions for keymaps.
--
-- The plain tidal.nvim commands are silent when they cannot work (GHCi
-- without SuperDirt connects to nothing; sending without a session is
-- ignored). These wrappers check the real state and tell the user what to do
-- instead of quietly doing nothing useful.

local M = {}

local state = require("tidal.core.state")

--- Is SuperDirt listening on UDP 57120? (fast /proc scan via ss)
function M.engine_up()
	vim.fn.system('ss -uln 2>/dev/null | grep -q ":57120"')
	return vim.v.shell_error == 0
end

--- Launch Tidal only if the engine is up; otherwise point to `tidalctl start`.
function M.launch()
	if not M.engine_up() then
		vim.notify(
			"SuperDirt не запущен — сначала `tidalctl start`",
			vim.log.levels.WARN,
			{ title = "TidalCycles" }
		)
		return
	end
	vim.cmd("TidalLaunch")
end

--- Send the current line; warn if the Tidal session is not running.
function M.send()
	if not state.ghci then
		vim.notify(
			"Tidal не запущен — <leader>tl или Ctrl+Enter",
			vim.log.levels.WARN,
			{ title = "TidalCycles" }
		)
		return
	end
	require("tidal").api.send_line()
end

--- Send each non-empty line as its own command.
--- @param lines string[]
local function send_lines_impl(lines)
	local api = require("tidal").api
	for _, line in ipairs(lines) do
		local text = line:gsub("^%s+", ""):gsub("%s+$", "")
		if text ~= "" then
			api.send(text)
		end
	end
end

--- Send each non-empty selected line as its own command.
function M.send_lines()
	local first = vim.fn.line("'<")
	local last = vim.fn.line("'>")
	send_lines_impl(vim.api.nvim_buf_get_lines(0, first - 1, last, false))
end

--- Is this line the start of a top-level Tidal statement?
--- @param line string
--- @return boolean
local function is_statement_start(line)
	local t = line:gsub("^%s+", "")
	return t:match("^d%d+ %$") ~= nil or t:match("^hush") ~= nil or t:match("^let ") ~= nil
end

--- Bracket delta of a line, ignoring strings (mini-notation chords like
--- "[0,7.02]" must not count as brackets).
--- @param line string
--- @return integer
local function bracket_delta(line)
	local unquoted = (line:gsub('"(.-)"', ""))
	local open = select(2, unquoted:gsub("[%[%(%{]", ""))
	local close = select(2, unquoted:gsub("[%]%)%}]", ""))
	return open - close
end

--- Line of the enclosing top-level statement (dN $ / hush / let), scanning
--- upward from the cursor. Returns nil if no statement header is found.
--- @return integer|nil
local function statement_start_line()
	local line = vim.fn.line(".")
	while line >= 1 do
		local t = vim.fn.getline(line):gsub("^%s+", "")
		if is_statement_start(t) then
			return line
		end
		line = line - 1
	end
	return nil
end

--- End line of the statement that starts at `start`, following brackets
--- across blank lines (a stack may contain empty lines between elements)
--- and trailing operator continuations like `# room 0.32` after `]` or
--- `d1 $ slow 2 $` followed by the next line.
--- @param start integer
--- @return integer
local function statement_end_line(start)
	local depth = 0
	local last = vim.fn.line("$")
	local line = start
	while line <= last do
		depth = depth + bracket_delta(vim.fn.getline(line))
		if depth == 0 then
			if line < last then
				local nx = vim.fn.getline(line + 1):gsub("^%s+", "")
				local cur = vim.fn.getline(line):gsub("%s+$", "")
				-- Next line starts with an operator, or this line ends with one:
				-- the expression continues.
				if nx ~= "" and nx:match("^[#|+~<>]") then
					line = line + 1
				elseif cur:match("[%$#|+~>]$") then
					line = line + 1
				else
					break
				end
			else
				break
			end
		else
			line = line + 1
		end
	end
	return line
end

--- How many top-level statements are in these lines?
--- @param lines string[]
--- @return integer
local function count_statements(lines)
	local n = 0
	for _, line in ipairs(lines) do
		if is_statement_start(line) then
			n = n + 1
		end
	end
	return n
end

--- Smart send: one multi-line expression under the cursor/selection is sent
--- as a single :{ ... :} block; several independent statements are sent
--- line-by-line. This replaces the "always send one line" Alt+Enter.
function M.send_smart()
	if not state.ghci then
		vim.notify(
			"Tidal не запущен — <leader>tl или Ctrl+Enter",
			vim.log.levels.WARN,
			{ title = "TidalCycles" }
		)
		return
	end

	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" then
		-- Visual selection: send as one block when it is a single expression.
		local sel = require("tidal.util.select").get_visual()
		if not sel then
			return
		end
		local selLines = sel.lines
		if #selLines > 1 and count_statements(selLines) <= 1 then
			require("tidal").api.send_multiline(selLines)
		else
			send_lines_impl(selLines)
		end
		return
	end

	local start = statement_start_line()
	if not start then
		-- No statement header above (bare expression): send the current line.
		require("tidal").api.send_line()
		return
	end
	local finish = statement_end_line(start)
	local lines = vim.api.nvim_buf_get_lines(0, start - 1, finish, false)
	if #lines > 1 and count_statements(lines) <= 1 then
		-- One expression spanning multiple lines: send the whole block at once.
		require("tidal").api.send_multiline(lines)
	else
		-- Single line, or several independent statements: line by line.
		send_lines_impl(lines)
	end
end

--- Hush everything; warn if no session.
function M.hush()
	if not state.ghci then
		vim.notify(
			"Tidal не запущен — нечего глушить",
			vim.log.levels.WARN,
			{ title = "TidalCycles" }
		)
		return
	end
	require("tidal.core.message").tidal.send_line("hush")
end

--- Insert a Shabda (https://shabda.ndre.gr) Freesound pack reslist into the
--- current buffer and send it to Tidal.
--- @param pack string pack name (e.g. "808", "amen")
--- @param opts? {send: boolean|nil} send after insert (default true)
function M.shabda(pack, opts)
	opts = opts or {}
	if pack == nil or pack == "" then
		vim.notify("usage: :TidalShabda <pack>", vim.log.levels.WARN, { title = "Shabda" })
		return
	end
	local line = '!reslist "https://shabda.ndre.gr/' .. pack .. '.json?licenses=by,cc0,by-nc"'
	-- insert below cursor
	local row = vim.fn.line(".")
	vim.api.nvim_buf_set_lines(0, row, row, false, { line })
	if opts.send == false then
		vim.notify("inserted: " .. line, vim.log.levels.INFO, { title = "Shabda" })
		return
	end
	if not state.ghci then
		vim.notify(
			"Shabda-строка вставлена; Tidal не запущен — <leader>tl",
			vim.log.levels.WARN,
			{ title = "Shabda" }
		)
		return
	end
	require("tidal.core.message").tidal.send_line(line)
end

return M
