local diagnostics = {};

local function handle_diagnostic_level (level, icon)
	local default = string.format("FancyDiagnostic%s", "Default");
	local default_icon_hl = string.format("FancyDiagnostic%sIcon", "Default");
	local bg = string.format("FancyDiagnostic%s", level);
	local icon_hl = string.format("FancyDiagnostic%sIcon", level);
	return {
		width = 3,
		line_hl_group = function (_, current)
			return current and bg or default;
		end,
		icon = function (_, current)
			return {
				{ "▌", current and icon_hl or default_icon_hl },
				{ icon, current and icon_hl or default_icon_hl },
				{ " ", current and bg or default },
			}
		end,
		padding = function (_, current)
			return {
				{ "▌", current and icon_hl or default_icon_hl },
				{ "  ", current and icon_hl or default_icon_hl },
				{ " ", current and bg or default },
			}
		end
	};
end

diagnostics.config = {
	keymap = "D",
	decoration_width = 4,
	width = function (items)
		local max = math.floor(vim.o.columns * 0.4);
		local use = 1
		for _, item in ipairs(items) do
			local width = vim.fn.strdisplaywidth(item.message or "");
			use = math.max(math.max(width, 1), max);
		end
		return use;
	end,
	max_height = function ()
		return math.floor(vim.o.lines * 0.4);
	end,
	beacon = {
		default = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "@comment", link = false }).fg;
				return fg and string.format("#%06x", fg) or "#9399b2";
			end,
			to = function ()
				local bg = vim.api.nvim_get_hl(0, { name = vim.o.statusline and "Cursorline" or "Normal", link = false }).bg;
				return bg and string.format("#%06x", bg) or "#1e1e2e";
			end,
			steps = 10,
			interval = 100,
		},
		[vim.diagnostic.severity.INFO] = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "FancyDiagnosticInfoIcon", link = false }).fg;
				return fg and string.format("#%06x", fg) or "#94e2d5";
			end
		},
		[vim.diagnostic.severity.HINT] = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "FancyDiagnosticHintIcon", link = false }).fg;
				return fg and string.format("#%06x", fg) or "#94e2d5";
			end
		},
		[vim.diagnostic.severity.WARN] = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "FancyDiagnosticWarnIcon", link = false }).fg;
				return fg and string.format("#%06x", fg) or "#f9e2af";
			end
		},
		[vim.diagnostic.severity.ERROR] = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "FancyDiagnosticErrorIcon", link = false }).fg;
				return fg and string.format("#%06x", fg) or "#f38ba8";
			end
		},
	},
	decorations = {
		[vim.diagnostic.severity.INFO] = handle_diagnostic_level("Info", "󰀨 "),
		[vim.diagnostic.severity.HINT] = handle_diagnostic_level("Hint", "󰁨 "),
		[vim.diagnostic.severity.WARN] = handle_diagnostic_level("Warn", " "),
		[vim.diagnostic.severity.ERROR] = handle_diagnostic_level("Error", "󰅙 "),
	},
};

local function eval(val, ...)
	if type(val) ~= "function" then return val; end
	local can_call, new_val = pcall(val, ...);
	if can_call and new_val ~= nil then return new_val; end
end

local function get_decorations (level, ...)
	local output = {};
	for k, v in pairs(diagnostics.config.decorations[level]) do
		output[k] = eval(v, ...);
	end
	return output;
end

local function get_beacon_config (level, ...)
	if not level or not diagnostics.config.beacon then return; end
	local output = {};
	for k, v in pairs(diagnostics.config.beacon[level]) do
		output[k] = eval(v, ...);
	end
	return output;
end

local function virt_text_to_sign (virt_text)
	local output = "";
	for _, item in ipairs(virt_text) do
		if type(item[2]) == "string" then
			output = output .. string.format("%%#%s#%s", item[2], item[1]) .. "%#Normal#";
		else
			output = output .. item[1];
		end
	end
	return output;
end

diagnostics.ns = vim.api.nvim_create_namespace("fancy_diagnostics");
diagnostics.buffer, diagnostics.window = nil, nil;
diagnostics.quad = nil;
diagnostics.sign_data = {};

diagnostics.__prepare = function ()
	if not diagnostics.buffer or not vim.api.nvim_buf_is_valid(diagnostics.buffer) then
		diagnostics.buffer = vim.api.nvim_create_buf(false, true);
	end
end

diagnostics.update_quad = function (quad, state)
	if not _G.__used_quads then return; end
	_G.__used_quads[quad] = state;
end

diagnostics.__win_args = function (window, w, h)
	local cursor = vim.api.nvim_win_get_cursor(window);
	local screenpos = vim.fn.screenpos(window, cursor[1], cursor[2]);
	local screen_width = vim.o.columns - 2;
	local screen_height = vim.o.lines - vim.o.cmdheight - 2;
	local quad_pref = { "bottom_right", "top_right", "bottom_left", "top_left" };
	local quads = {
		center = {
			relative = "editor", anchor = "NW",
			row = math.ceil((vim.o.lines - h) / 2),
			col = math.ceil((vim.o.columns - w) / 2),
			border = "rounded"
		},
		top_left = {
			condition = function ()
				if h >= screenpos.row then return false;
				elseif screenpos.curscol <= w then return false; end
				return true;
			end,
			relative = "cursor", border = { "╭", "─", "╮", "│", "┤", "─", "╰", "│" },
			anchor = "SE", row = 0, col = 1
		},
		top_right = {
			condition = function ()
				if h >= screenpos.row then return false;
				elseif screenpos.curscol + w > screen_width then return false; end
				return true;
			end,
			relative = "cursor", border = { "╭", "─", "╮", "│", "╯", "─", "├", "│" },
			anchor = "SW", row = 0, col = 0
		},
		bottom_left = {
			condition = function ()
				if screenpos.row + h > screen_height then return false;
				elseif screenpos.curscol <= w then return false; end
				return true;
			end,
			relative = "cursor", border = { "╭", "─", "┤", "│", "╯", "─", "╰", "│" },
			anchor = "NE", row = 1, col = 1
		},
		bottom_right = {
			condition = function ()
				if screenpos.row + h > screen_height then return false;
				elseif screenpos.curscol + w > screen_width then return false; end
				return true;
			end,
			relative = "cursor", border = { "├", "─", "╮", "│", "╯", "─", "╰", "│" },
			anchor = "NW", row = 1, col = 0
		},
	};

	for _, pref in ipairs(quad_pref) do
		if _G.__used_quads and _G.__used_quads[pref] == true then goto continue; end
		if not quads[pref] then goto continue; end
		local quad = quads[pref];
		local ran_cond, cond = pcall(quad.condition);
		if ran_cond and cond then
			diagnostics.quad = pref;
			return quad.border, quad.relative, quad.anchor, quad.row, quad.col;
		end
		::continue::
	end

	diagnostics.quad = "center";
	local fallback = quads.center;
	return fallback.border, fallback.relative, fallback.anchor, fallback.row, fallback.col;
end

diagnostics.close = function ()
	if diagnostics.window and vim.api.nvim_win_is_valid(diagnostics.window) then
		pcall(vim.api.nvim_win_close, diagnostics.window, true);
		diagnostics.window = nil;
		if diagnostics.quad then
			diagnostics.update_quad(diagnostics.quad, false);
			diagnostics.quad = nil;
		end
	end
end

diagnostics.__beacon = nil;

diagnostics.__integration = function (window, beacon_config)
	if package.loaded["markview"] then
		package.loaded["markview"].render(diagnostics.buffer, {
			enable = true, hybrid_mode = false
		}, { markdown_inline = { inline_codes = { virtual = true } } });
	end
	if package.loaded["scripts.beacon"] then
		if not diagnostics.__beacon then
			diagnostics.__beacon = require("scripts.beacon").new(window, beacon_config);
		else
			diagnostics.__beacon:update(window, beacon_config);
		end
		diagnostics.__beacon:start();
	end
end

_G.fancy_diagnostics_statuscolumn = function ()
	if vim.tbl_isempty(diagnostics.sign_data) then return ""; end
	local lnum = vim.v.lnum;
	local data = diagnostics.sign_data[lnum];
	if not data then return "";
	elseif vim.v.virtnum == 0 and data.start_row == lnum then
		return virt_text_to_sign(data.icon);
	else
		return virt_text_to_sign(data.padding or data.icon);
	end
end

diagnostics.hover = function (window)
	window = window or vim.api.nvim_get_current_win();
	local buffer = vim.api.nvim_win_get_buf(window);
	local cursor = vim.api.nvim_win_get_cursor(window);
	local items = vim.diagnostic.get(buffer, { lnum = cursor[1] - 1 });
	local already_open = diagnostics.window and vim.api.nvim_win_is_valid(diagnostics.window);

	if #items == 0 then
		diagnostics.close();
		vim.api.nvim_echo({ { " 󰾕 diagnostics.lua ", "DiagnosticVirtualTextWarn" }, { ": ", "@comment" }, { "No diagnostic under cursor", "@comment" } }, true, {});
		return;
	elseif already_open then
		vim.api.nvim_set_current_win(diagnostics.window);
		return;
	end

	if diagnostics.quad then diagnostics.update_quad(diagnostics.quad, false); end

	diagnostics.__prepare();
	vim.bo[diagnostics.buffer].ft = "markdown";
	vim.api.nvim_buf_clear_namespace(diagnostics.buffer, diagnostics.ns, 0, -1);
	vim.api.nvim_buf_set_lines(diagnostics.buffer, 0, -1, false, {});

	local W = eval(diagnostics.config.width, items);
	local D = eval(diagnostics.config.decoration_width, items);

	local height_calc_config = {
		relative = "editor", row = 0, col = 1,
		width = math.max(10, W - D), height = 2,
		style = "minimal", hide = true,
	};

	if not diagnostics.window or not vim.api.nvim_win_is_valid(diagnostics.window) then
		diagnostics.window = vim.api.nvim_open_win(diagnostics.buffer, false, height_calc_config);
	else
		vim.api.nvim_win_set_config(diagnostics.window, height_calc_config);
	end

	vim.wo[diagnostics.window].wrap = true;
	vim.wo[diagnostics.window].linebreak = true;
	vim.wo[diagnostics.window].breakindent = true;

	local diagnostic_lines = 0;
	local cursor_y = 1;
	local ranges = {};
	local start_row = 1;
	local level;
	diagnostics.sign_data = {};

	for i, item in ipairs(items) do
		local from = i == 1 and 0 or -1;
		local lines = vim.split(item.message, "\n", { trimempty = true })
		local start = item.col;
		local stop = item.end_col;
		local current = false;

		if cursor[2] >= start and cursor[2] <= stop then
			cursor_y = i;
			current = true;
		end

		vim.api.nvim_buf_set_lines(diagnostics.buffer, from, -1, false, lines);
		local decorations = get_decorations(item.severity, item, current);
		ranges[i] = { item.lnum, item.col };

		vim.api.nvim_buf_set_extmark(diagnostics.buffer, diagnostics.ns, diagnostic_lines, 0, {
			end_row = diagnostic_lines + #lines,
			line_hl_group = decorations.line_hl_group,
		});

		diagnostic_lines = diagnostic_lines + #lines;

		if current == true and (not level or item.severity < level) then
			level = item.severity;
		end

		for _ = 1, #lines do
			table.insert(diagnostics.sign_data, {
				start_row = start_row, current = current,
				width = decorations.width, icon = decorations.icon,
				line_hl_group = decorations.line_hl_group, padding = decorations.padding,
			});
		end
		start_row = start_row + #lines;
	end

	local beacon_config = vim.tbl_extend("force",
		get_beacon_config("default", {}, true),
		get_beacon_config(level, {}, true) or {}
	);

	local H = vim.api.nvim_win_text_height(diagnostics.window, { start_row = 0, end_row = -1 }).all;
	local _, relative, anchor, row, col = diagnostics.__win_args(window, W, H);

	local win_config = {
		relative = relative or "cursor",
		row = row or 0, col = col or 0,
		width = W, height = H,
		anchor = anchor, border = "none",
		style = "minimal", hide = false,
	};

	vim.api.nvim_win_set_config(diagnostics.window, win_config);
	vim.api.nvim_win_set_cursor(diagnostics.window, { cursor_y, 0 });
	diagnostics.update_quad(diagnostics.quad, true);

	vim.wo[diagnostics.window].signcolumn = "no";
	vim.wo[diagnostics.window].statuscolumn = "%!v:lua.fancy_diagnostics_statuscolumn()";
	vim.wo[diagnostics.window].conceallevel = 3;
	vim.wo[diagnostics.window].concealcursor = "ncv";
	vim.wo[diagnostics.window].winhl = "FloatBorder:@comment,Normal:Normal";

	diagnostics.__integration(window, beacon_config);

	vim.api.nvim_buf_set_keymap(diagnostics.buffer, "n", "<CR>", "", {
		desc = "Go to diagnostic location",
		callback = function ()
			local _cursor = vim.api.nvim_win_get_cursor(diagnostics.window);
			local location = ranges[_cursor[1]];
			if location then
				location[1] = location[1] + 1;
				vim.api.nvim_win_set_cursor(window, location);
				vim.api.nvim_set_current_win(window);
				diagnostics.close();
			end
		end
	});

	vim.api.nvim_buf_set_keymap(diagnostics.buffer, "n", "q", "", {
		desc = "Exit diagnostics window",
		callback = function ()
			pcall(vim.api.nvim_set_current_win, window);
			diagnostics.close();
		end
	});
end

diagnostics.setup = function (config)
	if type(config) == "table" then
		diagnostics.config = vim.tbl_extend("force", diagnostics.config, config);
	end
	if diagnostics.config.keymap then
		vim.api.nvim_set_keymap("n", diagnostics.config.keymap, "", {
			callback = diagnostics.hover,
			desc = "Fancy diagnostics hover",
		});
	end
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		callback = function ()
			local win = vim.api.nvim_get_current_win();
			if diagnostics.window and win ~= diagnostics.window then
				diagnostics.close();
				if diagnostics.quad then
					diagnostics.update_quad(diagnostics.quad, false);
					diagnostics.quad = nil;
				end
			end
		end
	});
end

return diagnostics;
