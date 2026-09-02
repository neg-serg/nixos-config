-- Mercury fuzzy matching algorithm (Lua port).
-- Original: Copyright (C) 2010 Matt Tolton (Quicksilver/LiquidMetal based).
-- Ported from /tmp/lusty (github.com/sjbach/lusty) src/mercury.rb.
--
-- Port notes:
--   * Ruby strings are 0-based, Lua 1-based; indexes below were shifted once.
--   * The recursive search is bounded by BRANCH_LIMIT like the original.
--   * The original compared "abbrev_idx == index" (pattern position vs match
--     position); that quirk is preserved for identical ranking behaviour.

local SCORE = {
  no_match = 0.0, -- do not change; assumed to be 0.0
  exact = 1.0,
  match = 0.9,
  trailing = 0.7,
  trailing_but_started = 0.80,
  buffer = 0.70,
  buffer_but_started = 0.80,
}

local BRANCH_LIMIT = 100

local SEPARATORS = { [' '] = true, ['\t'] = true, ['/'] = true, ['.'] = true, ['_'] = true, ['-'] = true }

--- Score how well the abbreviation matches a string (case-insensitive).
--- Returns 0.0 when there is no match.
--- @param str string
--- @param abbrev string
--- @return number
local function score(str, abbrev)
  if abbrev == '' then
    return SCORE.trailing
  end
  if #abbrev > #str then
    return 0.0
  end

  local lower_str = str:lower()
  local lower_abbrev = abbrev:lower()
  local branches = 0

  -- Recursive match scorer.  Mirrors raw_score(abbrev_idx, match_idx,
  -- score_idx, first_char_matched) from the original.
  local function raw_score(abbrev_idx, match_idx, score_idx, first_char_matched)
    if abbrev_idx > #lower_abbrev then
      return 0.0
    end
    local want = lower_abbrev:sub(abbrev_idx, abbrev_idx)
    -- string.find with plain=true; match_idx is a 1-based start position.
    local index = lower_str:find(want, match_idx, true)
    if not index then
      return 0.0
    end

    local s
    if abbrev_idx == index then
      s = SCORE.exact
    else
      s = SCORE.match
    end

    local started = (index == 1) or first_char_matched

    -- Word-boundary bonus for the gap since the last matched character.
    if index > score_idx then
      local buffer_score = started and SCORE.buffer_but_started or SCORE.buffer
      local prev = index > 1 and str:sub(index - 1, index - 1) or nil
      if prev and SEPARATORS[prev] then
        s = s + SCORE.match
        s = s + buffer_score * ((index - 1) - score_idx)
      elseif prev then
        local c = str:byte(index, index)
        if c and c >= string.byte('A') and c <= string.byte('Z') then
          s = s + buffer_score * (index - score_idx)
        end
      end
    end

    if abbrev_idx == #lower_abbrev then
      -- Last pattern character matched; award the trailing part.
      local trailing_score = started and SCORE.trailing_but_started or SCORE.trailing
      s = s + trailing_score * (#str - index)
    else
      local tail_score = raw_score(abbrev_idx + 1, index + 1, index + 1, started)
      if tail_score == 0.0 then
        return 0.0
      end
      s = s + tail_score
    end

    if branches < BRANCH_LIMIT then
      branches = branches + 1
      local alternate = raw_score(abbrev_idx, index + 1, score_idx, first_char_matched)
      if alternate > s then
        s = alternate
      end
    end

    return s
  end

  local raw = raw_score(1, 1, 1, false)
  return raw / #str
end

return { score = score }
