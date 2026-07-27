--[[
*Dynamic* highlights for `Neovim` to match the current `colorscheme`.

Usage,

```lua
require("highlights").setup();
```
]]
local highlights = {};

local function clamp (c)
	return math.min(math.max(0, math.floor(c)), 255);
end

highlights.rgb = function (input)
	local lookup = vim.api.nvim_get_color_map();
	local hex;

	if type(input) == "string" and (lookup[input]) then
		hex = string.format("#%06x", lookup[input]);
	elseif type(input) == "number" then
		hex = string.format("%06x", input);
	else
		hex = type(input) == "string" and input or "#FFFFFF";
	end

	return {
		r = tonumber(string.sub(hex, 2, 3), 16),
		g = tonumber(string.sub(hex, 4, 5), 16),
		b = tonumber(string.sub(hex, 6, 7), 16),
	}, type(input) ~= "string" and type(input) ~= "number";
end

highlights.mix = function (c1, c2, p1, p2)
	local out = {};
	for k, v in pairs(c1) do
		if c2[k] then out[k] = (v * p1) + (c2[k] * p2); else out[k] = v; end
	end
	return out;
end

highlights.rgb_to_hex = function (color)
	return string.format("#%02x%02x%02x", clamp(color.r), clamp(color.g), clamp(color.b));
end

highlights.srgb_to_oklab = function (c)
	local l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	local m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	local s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;

	local l_ = math.pow(l, 1 / 3);
	local m_ = math.pow(m, 1 / 3);
	local s_ = math.pow(s, 1 / 3);

	return {
		L = 0.2104542553 *l_ + 0.7936177850 *m_ - 0.0040720468 *s_,
		a = 1.9779984951 *l_ - 2.4285922050 *m_ + 0.4505937099 *s_,
		b = 0.0259040371 *l_ + 0.7827717662 *m_ - 0.8086757660 *s_,
	};
end

highlights.oklab_to_srgb = function (c)
	local l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b;
	local m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b;
	local s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b;

	local l = l_*l_*l_;
	local m = m_*m_*m_;
	local s = s_*s_*s_;

	return {
		r = clamp( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		g = clamp(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		b = clamp(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
	};
end

highlights.set_hl = function (name, value)
	local found, v = pcall(vim.api.nvim_get_hl, 0, { name = name, create = false, link = false });
	local is_empty = vim.deep_equal(v, vim.empty_dict());
	if found and not is_empty then return; end
	value.default = not is_empty;
	pcall(vim.api.nvim_set_hl, 0, name, value);
end

highlights.create = function (array)
	if type(array) == "string" then
		if not highlights[array] then return; end
		array = highlights[array];
	end

	local hls = vim.tbl_keys(array) or {};
	table.sort(hls);
	for _, hl in ipairs(hls) do
		local _value = array[hl];
		local value;
		if type(_value) == "function" then
			local s, v = pcall(_value);
			value = s and v or {};
		else
			value = _value;
		end
		if vim.islist(value) and #value > 0 then
			for _, entry in ipairs(value) do
				highlights.set_hl(entry.group_name, entry.value);
			end
		elseif type(value) == "table" then
			highlights.set_hl(hl, value);
		end
	end
end

local is_dark = function (on_light, on_dark)
	return vim.o.background == "dark" and on_dark or on_light;
end

highlights.get_property = function (property, groups, light, dark)
	local val;
	for _, item in ipairs(groups) do
		local hl = vim.api.nvim_get_hl(0, { name = item, link = false, create = false });
		if vim.fn.hlexists(item) == 1 and hl[property] then
			val = hl[property];
			break;
		end
	end
	local fallback = is_dark(light, dark);
	if property == "fg" or property == "bg" or property == "sp" then
		local converted, as_fallback = highlights.rgb(val or fallback);
		return as_fallback == false and converted or nil;
	else
		return val or fallback;
	end
end

highlights.inherit = function (from, with, properties)
	local _from = vim.api.nvim_get_hl(0, { name = from, link = false, create = false }) or {};
	local output = {};
	if properties and vim.islist(properties) then
		for _, property in ipairs(properties) do
			output[property] = _from[property];
		end
	else
		output = _from;
	end
	return vim.tbl_extend("force", output, with);
end

highlights.icon_hl = function (n)
	return highlights.inherit("MarkviewCode", {
		fg = vim.api.nvim_get_hl(0, {
			name = string.format("MarkviewPalette%d", n), link = false, create = false
		}).fg
	});
end

highlights.groups = {
	FadedBg = function ()
		local bg = highlights.srgb_to_oklab(highlights.get_property("fg", { "Normal" }, "#EFF1F5", "#1E1E2E"));
		local alpha = vim.g.faded_alpha or (vim.o.background == "light" and 0.25 or 0.5);
		local faded = { L = bg.L * alpha, a = bg.a, b = bg.b };
		return { bg = highlights.rgb_to_hex(highlights.oklab_to_srgb(faded)) };
	end,

	Modified = function ()
		return { { group_name = "@lsp.type.comment.lua", value = {} } };
	end,

	Diagnostic = function ()
		local bg = highlights.srgb_to_oklab(highlights.get_property("bg", { "Normal" }, "#EFF1F5", "#1E1E2E"));
		local alpha = vim.g.diagnostic_alpha or 0.1;
		local output = {};

		local function handle_kind (kind)
			local color_map = {
				Default = { "#7C7F93", "#9399B2" },
				Info = { "#179299", "#94E2D5" },
				Hint = { "#179299", "#94E2D5" },
				Warn = { "#DF8E1D", "#F9E2AF" },
				Error = { "#D20F39", "#F38BA8" },
			};
			local this_color = color_map[kind] or color_map.Default;
			local fg = highlights.srgb_to_oklab(highlights.get_property("fg", {
				kind == "Default" and "@comment" or string.format("Diagnostic%s", kind),
			}, this_color[1], this_color[2]));
			local new_bg = highlights.mix(fg, bg, alpha, 1 - alpha);
			table.insert(output, {
				group_name = string.format("FancyDiagnostic%s", kind),
				value = { bg = highlights.rgb_to_hex(highlights.oklab_to_srgb(new_bg)), fg = highlights.rgb_to_hex(highlights.oklab_to_srgb(fg)) },
			});
			table.insert(output, {
				group_name = string.format("FancyDiagnostic%sIcon", kind),
				value = { bg = highlights.rgb_to_hex(highlights.oklab_to_srgb(fg)), fg = highlights.rgb_to_hex(highlights.oklab_to_srgb(bg)) },
			});
		end

		handle_kind("Default");
		handle_kind("Info");
		handle_kind("Hint");
		handle_kind("Warn");
		handle_kind("Error");
		return output;
	end,
};

highlights.setup = function (opt)
	if type(opt) == "table" then
		highlights.groups = vim.tbl_extend("force", highlights.groups, opt);
	end
	highlights.create(highlights.groups);
end

return highlights;
