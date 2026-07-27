local function last_width (str)
	local chars = vim.fn.strchars(str);
	local reduced = vim.fn.strcharpart(str, 0, chars - 1);
	return vim.fn.strdisplaywidth(str) - vim.fn.strdisplaywidth(reduced);
end

local function get_win (...)
	for _, win in ipairs({ ... }) do
		if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
			return win;
		end
	end
	return vim.api.nvim_get_current_win();
end

local M = {};

M.config = {
	set_keymap = true,
	on_motions = {
		gg = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "Comment", create = false, link = false }).fg;
				return fg or { 147, 153, 178 };
			end,
		},
		G = {
			from = function ()
				local fg = vim.api.nvim_get_hl(0, { name = "Conditional", create = false, link = false }).fg;
				return fg or { 203, 166, 247 };
			end,
		},
	},
	default = {
		from = function ()
			local colors = {
				Function = vim.api.nvim_get_hl(0, { name = "Function", create = false, link = false }).fg,
				Character = vim.api.nvim_get_hl(0, { name = "Character", create = false, link = false }).fg,
				Constant = vim.api.nvim_get_hl(0, { name = "Constant", create = false, link = false }).fg,
				Conditional = vim.api.nvim_get_hl(0, { name = "Conditional", create = false, link = false }).fg,
				Define = vim.api.nvim_get_hl(0, { name = "Define", create = false, link = false }).fg,
				Type = vim.api.nvim_get_hl(0, { name = "Type", create = false, link = false }).fg,
				DiagnosticError = vim.api.nvim_get_hl(0, { name = "DiagnosticError", create = false, link = false }).fg,
				DiagnosticOk = vim.api.nvim_get_hl(0, { name = "DiagnosticOk", create = false, link = false }).fg,
			};
			local keys = vim.tbl_keys(colors);
			local K = math.random(1, #keys);
			return colors[keys[K]] or { 203, 166, 247 };
		end,
		to = function ()
			local bg = vim.api.nvim_get_hl(0, { name = "CursorLine", create = false, link = false }).bg;
			return bg or { 30, 30, 46 };
		end,
		steps = 10,
		interval = 100,
	}
};

local beacon = {};
beacon.__index = beacon;

function beacon:__gradient ()
	local function eval (val, ...)
		if type(val) == "string" then
			local R, G, B = string.match(val, "^#?(..?)(..?)(..?)$")
			return { tonumber(R, 16), tonumber(G, 16), tonumber(B, 16) };
		elseif type(val) == "number" then
			local hex = string.format("%x", val);
			hex = string.sub(hex, 0, 6);
			local R, G, B = string.match(hex, "^(..?)(..?)(..?)$")
			return { tonumber(R, 16), tonumber(G, 16), tonumber(B, 16) };
		elseif vim.islist(val) == true and type(val[1]) == "number" then
			return val;
		elseif pcall(val) then
			local _, _val = pcall(val, ...);
			return type(_val) ~= "function" and eval(_val, ...) or { 0, 0, 0 };
		end
		return { 0, 0, 0 };
	end

	local from = eval(self.from_color);
	local to = eval(self.to_color);

	local function lerp (n, y)
		local _from = from[n];
		local _to = to[n];
		return math.floor(_from + ((_to - _from) * y));
	end

	local gradient = {};
	local corrected_steps = self.steps - 1;

	for s = 0, corrected_steps do
		local multiplier = s / corrected_steps;
		local name = string.format("Beacon%dStep%d", self.ns, s);
		local color = string.format("#%02x%02x%02x", lerp(1, multiplier), lerp(2, multiplier), lerp(3, multiplier));
		table.insert(gradient, name);
		vim.api.nvim_set_hl(0, name, { bg = color });
	end
	return gradient;
end

function beacon:__list_render ()
	if vim.wo[self.window].list == false then return; end
	local Y, X = self.pos[1] - 1, self.pos[2];
	vim.api.nvim_buf_clear_namespace(self.buffer, self.ns, Y, Y + 1);
	local line = vim.api.nvim_buf_get_lines(self.buffer, Y, Y + 1, false)[1] or "";
	local before = vim.fn.strpart(line, 0, X);
	local after = vim.fn.strpart(line, X);
	local C = 1;
	local removed = "";
	local virt_eol = {};

	while C <= #self.colors do
		local first = vim.fn.strcharpart(after, 0, 1);
		removed = removed .. first;
		local width = last_width(before .. removed);
		if after == "" then
			table.insert(virt_eol, { " ", self.colors[C] });
			C = C + 1;
		elseif width > 1 then
			local col = #(before .. removed) - #first;
			local virt_text = {};
			while width >= 1 do
				table.insert(virt_text, { " ", self.colors[C] });
				C = C + 1;
				width = width - 1;
			end
			vim.api.nvim_buf_set_extmark(self.buffer, self.ns, Y, col, {
				virt_text_pos = "overlay", virt_text = virt_text, hl_mode = "combine"
			});
		else
			local col = #(before .. removed) - #first;
			vim.api.nvim_buf_set_extmark(self.buffer, self.ns, Y, col, {
				end_col = col + 1, hl_group = self.colors[C],
			});
			C = C + 1;
		end
		after = vim.fn.strcharpart(after, 1);
	end
	if #virt_eol > 0 then
		local col = #line;
		pcall(vim.api.nvim_buf_set_extmark, self.buffer, self.ns, Y, col, {
			virt_text_pos = "inline", virt_text = virt_eol,
		})
	end
end

function beacon:__nolist_render ()
	if vim.wo[self.window].list == true then return; end
	local Y, X = self.pos[1] - 1, self.pos[2];
	vim.api.nvim_buf_clear_namespace(self.buffer, self.ns, Y, Y + 1);
	local line = vim.api.nvim_buf_get_lines(self.buffer, Y, Y + 1, false)[1] or "";
	local before = vim.fn.strpart(line, 0, X);
	local after = vim.fn.strpart(line, X);
	local C = 1;
	local removed = "";
	local virt_eol = {};

	while C <= #self.colors do
		local first = vim.fn.strcharpart(after, 0, 1);
		removed = removed .. first;
		local width = last_width(before .. removed);
		if after == "" then
			table.insert(virt_eol, { " ", self.colors[C] });
			C = C + 1;
		elseif width > 1 then
			local col = #(before .. removed) - #first;
			local virt_text = {};
			while width >= 1 do
				if X == col and width > 1 then
					table.insert(virt_text, { " " });
				else
					table.insert(virt_text, { " ", self.colors[C] });
					C = C + 1;
				end
				width = width - 1;
			end
			vim.api.nvim_buf_set_extmark(self.buffer, self.ns, Y, col, {
				virt_text_pos = "overlay", virt_text = virt_text, hl_mode = "combine"
			});
		else
			local col = #(before .. removed) - #first;
			vim.api.nvim_buf_set_extmark(self.buffer, self.ns, Y, col, {
				end_col = col + 1, hl_group = self.colors[C],
			});
			C = C + 1;
		end
		after = vim.fn.strcharpart(after, 1);
	end
	if #virt_eol > 0 then
		local col = #line;
		vim.api.nvim_buf_set_extmark(self.buffer, self.ns, Y, col, {
			virt_text_pos = "inline", virt_text = virt_eol,
		})
	end
end

function beacon:render ()
	if type(self.window) == "number" and vim.api.nvim_win_is_valid(self.window) then
		self:__list_render();
		self:__nolist_render();
	end
	table.remove(self.colors, 1);
	self.step = self.step + 1;
end

function beacon:update (window, config)
	local _config = type(config) == "table" and config or {};
	self.window = get_win(window, self.window, vim.api.nvim_get_current_win());
	self.buffer = vim.api.nvim_win_get_buf(self.window);
	self.pos = vim.api.nvim_win_get_cursor(self.window);
	self.from_color = _config.from or self.from_color;
	self.to_color = _config.to or self.to_color;
	self.interval = _config.interval or self.interval;
	self.steps = _config.steps or self.steps;
	self.step = 0;
	self.colors = self:__gradient();
end

function beacon:stop ()
	if not self.timer then return; end
	self.timer:stop();
end

function beacon:start ()
	if not self.timer then return; end
	self.timer:stop();
	pcall(vim.api.nvim_buf_clear_namespace, self.buffer, self.ns, 0, -1);
	self.timer:start(0, self.interval, vim.schedule_wrap(function ()
		if self.step > self.steps then
			pcall(vim.api.nvim_buf_clear_namespace, self.buffer, self.ns, 0, -1);
			self:stop();
			return;
		end
		self:render();
	end));
end

M.new = function (window, config)
	local _config = type(config) == "table" and config or M.config.default;
	local instance = setmetatable({}, beacon);
	instance.ns = vim.api.nvim_create_namespace("");
	instance.window = get_win(window, vim.api.nvim_get_current_win());
	instance.buffer = vim.api.nvim_win_get_buf(instance.window);
	instance.pos = vim.api.nvim_win_get_cursor(instance.window);
	instance.from_color = _config.from;
	instance.to_color = _config.to;
	instance.interval = _config.interval;
	instance.steps = _config.steps;
	instance.step = 0;
	instance.colors = instance:__gradient();
	instance.timer = vim.uv.new_timer();
	return instance;
end

M.setup = function (config)
	if type(config) == "table" then
		M.config = vim.tbl_extend("force", M.config.default, config);
	end
end

return M;
