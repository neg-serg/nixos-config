-- Smart subsequence fuzzy scorer (fzy-style) for LustyExplorer.
--
-- Used by default for ranking matches while typing; the original Mercury
-- scorer stays available via g:LustyExplorerFuzzyEngine = 'mercury'.
--
-- Scoring ideas:
--   * matched characters earn a base score plus a word-boundary bonus when
--     they start a segment (string start, after '/' '-' '_' '.' ' '), or on
--     a camelCase boundary;
--   * consecutive matched characters in the haystack get a small bonus;
--   * skipped characters between matches cost a little (inner gap), and a
--     late first match is penalised, so prefix/segment-leading matches win.

local M = {}

local LEADING_PENALTY = 0.012 -- per skipped char before the first match
local INNER_GAP = 0.02       -- per skipped char between two matches
local CONSECUTIVE_BONUS = 0.05

local function is_upper(b)
  return b >= 65 and b <= 90
end
local function is_lower(b)
  return b >= 97 and b <= 122
end

--- Boundary bonus for a haystack byte position (1-based).
local function bonus_for(str, i)
  if i == 1 then
    return 0.9
  end
  local ch = str:sub(i, i)
  if ch == '/' then
    return 0.9
  end
  local prev = str:sub(i - 1, i - 1)
  if prev == '-' or prev == '_' or prev == ' ' or prev == '.' then
    return 0.8
  end
  if prev == '/' then
    return 0.9
  end
  -- camelCase: lower-case letter followed by an upper-case one.
  local pb = str:byte(i - 1, i - 1)
  local cb = str:byte(i, i)
  if pb and cb and is_lower(pb) and is_upper(cb) then
    return 0.7
  end
  return 0.0
end

-- Subsequence check (case-insensitive).
local function has_match(lower_str, lower_abbrev)
  local a, b = 1, 1
  while a <= #lower_abbrev and b <= #lower_str do
    if lower_abbrev:sub(a, a) == lower_str:sub(b, b) then
      a = a + 1
    end
    b = b + 1
  end
  return a > #lower_abbrev
end

--- Score how well `abbrev` matches `str` (case-insensitive).
--- @param str string
--- @param abbrev string
--- @return number (0.0 when there is no match)
function M.score(str, abbrev)
  if abbrev == '' then
    return 0.75 -- neutral score for an empty query
  end
  if #abbrev > #str then
    return 0.0
  end

  local lower_str = str:lower()
  local lower_abbrev = abbrev:lower()
  if not has_match(lower_str, lower_abbrev) then
    return 0.0
  end

  local n = #lower_abbrev
  local m = #lower_str

  -- Rolling DP rows: prev[j] holds the best score for the previous pattern
  -- prefix ending exactly at haystack position j.
  local prev = {}
  local cur = {}
  local best = -math.huge

  for i = 1, n do
    -- Running max of (prev[k] + INNER_GAP * k) over k < j enables the
    -- inner-gap transition in O(1) per cell.
    local best_gap = -math.huge
    for j = 1, m do
      local score_j = nil
      if lower_abbrev:sub(i, i) == lower_str:sub(j, j) then
        local bon = bonus_for(str, j)
        if i == 1 then
          score_j = bon - LEADING_PENALTY * (j - 1)
        else
          local cand = -math.huge
          if prev[j - 1] ~= nil then
            cand = prev[j - 1] + CONSECUTIVE_BONUS
          end
          if best_gap > -math.huge then
            local via_gap = best_gap - INNER_GAP * (j - 1)
            if via_gap > cand then
              cand = via_gap
            end
          end
          if cand > -math.huge then
            score_j = cand + bon
          end
        end
      end
      cur[j] = score_j
      if score_j ~= nil and i == n and score_j > best then
        best = score_j
      end
      -- Allow prev[j] to serve gap transitions for positions after j.
      if prev[j] ~= nil then
        local with_k = prev[j] + INNER_GAP * j
        if with_k > best_gap then
          best_gap = with_k
        end
      end
    end
    prev, cur = cur, prev
  end

  if best <= -math.huge / 2 then
    return 0.0
  end
  return best
end

return M
