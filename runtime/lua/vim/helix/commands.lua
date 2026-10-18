-- Helix command calculations over a transient buffer snapshot.
-- Native core owns persistent selections, editing, and undo.
-- Positions here are zero-based half-open UTF-8 byte ranges.
-- Derived from helix.vim under MIT; see contrib/helix/LICENSE-helix.vim.
local M, Engine = {}, {}
Engine.__index = Engine
local function copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == 'table' and copy(v) or v
  end
  return out
end
M.copy = copy
local indexed_text, line_starts
local function index(text)
  if indexed_text == text then
    return line_starts
  end
  indexed_text, line_starts = text, { 0 }
  local p = 1
  while true do
    local newline = text:find('\n', p, true)
    if not newline then
      break
    end
    line_starts[#line_starts + 1], p = newline, newline + 1
  end
  return line_starts
end
local function continuation(b)
  return b and b >= 128 and b < 192
end
local grapheme_text, following, preceding, boundaries
local function graphemes(text)
  if grapheme_text == text then
    return
  end
  grapheme_text, following, preceding, boundaries = text, {}, {}, { 0 }
  local offset = 0
  -- Neovim's regex splitter uses its native extended-grapheme implementation,
  -- including combining characters and ZWJ emoji. Keep ASCII fast paths below.
  for _, character in ipairs(vim.fn.split(text, [[\zs]])) do
    local finish = offset + #character
    following[offset], preceding[finish] = finish, offset
    boundaries[#boundaries + 1] = finish
    offset = finish
  end
end
local function grapheme_boundary(text, p)
  graphemes(text)
  local left, right = 1, #boundaries
  while left < right do
    local middle = math.floor((left + right + 1) / 2)
    if boundaries[middle] <= p then
      left = middle
    else
      right = middle - 1
    end
  end
  return boundaries[left]
end
function M.next(text, p)
  if (text:byte(p + 1) or 0) >= 128 or (text:byte(p + 2) or 0) >= 128 then
    graphemes(text)
    return following[grapheme_boundary(text, p)] or #text
  end
  p = math.min(#text, p + 1)
  while p < #text and continuation(text:byte(p + 1)) do
    p = p + 1
  end
  return p
end
function M.prev(text, p)
  if (text:byte(p) or 0) >= 128 then
    graphemes(text)
    return preceding[grapheme_boundary(text, p)] or 0
  end
  p = math.max(0, p - 1)
  while p > 0 and continuation(text:byte(p + 1)) do
    p = p - 1
  end
  return p
end
function M.boundary(text, p)
  p = math.min(#text, math.max(0, p))
  if (text:byte(p + 1) or 0) >= 128 then
    return grapheme_boundary(text, p)
  end
  while p > 0 and continuation(text:byte(p + 1)) do
    p = p - 1
  end
  return p
end
function M.position(text, p)
  p = math.min(#text, math.max(0, p))
  local starts = index(text)
  local left, right = 1, #starts
  while left < right do
    local middle = math.floor((left + right + 1) / 2)
    if starts[middle] <= p then
      left = middle
    else
      right = middle - 1
    end
  end
  return left - 1, p - starts[left]
end
function M.offset(text, row, col)
  local starts = index(text)
  row = math.max(0, row)
  local start = starts[row + 1]
  if not start then
    return #text
  end
  local finish = starts[row + 2] and starts[row + 2] - 1 or #text
  return M.boundary(text, math.min(start + math.max(0, col), finish))
end
local function line_bounds(text, p)
  local row = M.position(text, p)
  local first = M.offset(text, row, 0)
  local newline = text:find('\n', first + 1, true)
  return first, newline and newline - 1 or #text, newline or #text
end
local function class(text, p, long)
  local c = text:sub(p + 1, M.next(text, p))
  if c == '' or c:match('%s') then
    return 0
  end
  local kind = vim.fn.charclass(c)
  if long and kind > 0 then
    return 1
  end
  return kind
end
function M.new(text, position, opts)
  opts = opts or {}
  local self = setmetatable({
    text = text or '',
    selections = {},
    primary = 1,
    mode = 'normal',
    pending = '',
    count = '',
    register = {},
    display_width = opts.display_width,
    surrounds = opts.surrounds,
  }, Engine)
  self:cursor(position or 0)
  return self
end
function Engine:cursor(p)
  p = M.boundary(self.text, p)
  self.selections, self.primary = { { start = p, finish = M.next(self.text, p) } }, 1
end
function Engine:head(s)
  return s.backward and s.start or (s.finish > s.start and M.prev(self.text, s.finish) or s.start)
end
function Engine:normalize()
  local primary = self.selections[self.primary]
  table.sort(self.selections, function(a, b)
    if a.start == b.start then
      return a.finish < b.finish
    end
    return a.start < b.start
  end)
  local out = {}
  for _, s in ipairs(self.selections) do
    s.start, s.finish = M.boundary(self.text, s.start), M.boundary(self.text, s.finish)
    s.finish = math.max(s.start, s.finish)
    local last = out[#out]
    if last and (s.start < last.finish or s.start == last.start) then
      last.finish = math.max(last.finish, s.finish)
      if primary == s then
        primary = last
      end
    else
      out[#out + 1] = s
    end
  end
  if #out == 0 then
    out = { { start = 0, finish = M.next(self.text, 0) } }
  end
  self.selections, self.primary = out, 1
  for i, s in ipairs(out) do
    if primary == s then
      self.primary = i
    end
  end
end
-- Edits are computed against one snapshot, sorted once, and applied together.
-- Optional ranges permit paste/backspace without mutating the undo selections.
function Engine:replace(values, insertion, ranges)
  self:normalize()
  local edits = {}
  for i, s in ipairs(ranges or self.selections) do
    edits[#edits + 1] = {
      start = s.start,
      finish = s.finish,
      value = type(values) == 'table' and (values[i] or values[1] or '') or values,
      primary = i == self.primary,
    }
  end
  table.sort(edits, function(a, b)
    return a.start < b.start
  end)
  local combined = {}
  for _, e in ipairs(edits) do
    local last = combined[#combined]
    if last and (e.start < last.finish or e.start == last.start) then
      -- Deletions may overlap after adjacent insertion points backspace together.
      assert(e.value == '' and last.value == '', 'overlapping replacement ranges')
      last.finish, last.primary = math.max(last.finish, e.finish), last.primary or e.primary
    else
      combined[#combined + 1] = e
    end
  end
  if self.on_edit then
    self.on_edit(combined, self.text)
  end
  local chunks, sels, previous, delta, primary = {}, {}, 0, 0, 1
  for i, e in ipairs(combined) do
    chunks[#chunks + 1] = self.text:sub(previous + 1, e.start)
    chunks[#chunks + 1] = e.value
    local p = e.start + delta
    sels[i] = insertion and { start = p + #e.value, finish = p + #e.value }
      or { start = p, finish = p + #e.value }
    if e.primary then
      primary = i
    end
    delta, previous = delta + #e.value - (e.finish - e.start), e.finish
  end
  chunks[#chunks + 1] = self.text:sub(previous + 1)
  local text = table.concat(chunks)
  self.text, self.selections, self.primary = text, sels, primary
  if not insertion then
    for _, s in ipairs(sels) do
      if s.start == s.finish then
        s.finish = M.next(text, s.start)
      end
    end
  end
  self:normalize()
end
function Engine:yank()
  self.register = {}
  for i, s in ipairs(self.selections) do
    self.register[i] = self.text:sub(s.start + 1, s.finish)
  end
end
function Engine:paste_values()
  if #self.register == #self.selections then
    return self.register
  end
  return table.concat(self.register, '\n')
end
function Engine:insert(after, change)
  self.mode = 'insert'
  if change then
    self:yank()
    self:replace('', true)
  else
    for _, s in ipairs(self.selections) do
      local p = after and s.finish or s.start
      s.start, s.finish, s.backward, s.goal = p, p, nil, nil
    end
    self:normalize()
  end
end
function Engine:backspace(forward, word)
  local ranges = {}
  for i, s in ipairs(self.selections) do
    local a, b = s.start, s.start
    if forward then
      b = M.next(self.text, b)
    else
      a = M.prev(self.text, a)
      if word then
        while a > 0 and class(self.text, a) == 0 do
          a = M.prev(self.text, a)
        end
        local cls = class(self.text, a)
        while a > 0 and class(self.text, M.prev(self.text, a)) == cls do
          a = M.prev(self.text, a)
        end
      end
    end
    ranges[i] = { start = a, finish = b }
  end
  self:replace('', true, ranges)
end
function Engine:column(p)
  local first = line_bounds(self.text, p)
  if self.display_width then
    return self.display_width(self.text:sub(first + 1, p))
  end
  local col = 0
  while first < p do
    first, col = M.next(self.text, first), col + 1
  end
  return col
end
function Engine:offset_column(row, column)
  local first = M.offset(self.text, row, 0)
  local _, last = line_bounds(self.text, first)
  local p, col = first, 0
  while p < last do
    local nextp = M.next(self.text, p)
    local nextcol = self.display_width and self.display_width(self.text:sub(first + 1, nextp))
      or col + 1
    if nextcol > column then
      break
    end
    p, col = nextp, nextcol
  end
  return p
end
function Engine:move_word(key, count)
  local text = self.text
  local backward = key == 'b' or key == 'B'
  local ending = key == 'e' or key == 'E'
  local long = key == 'W' or key == 'B' or key == 'E'
  local function category(p)
    if text:sub(p + 1, p + 1) == '\n' then
      return -1
    end
    return class(text, p, long)
  end
  local function advance(p)
    return backward and M.prev(text, p) or M.next(text, p)
  end
  local function ahead(p)
    return backward and M.prev(text, p) or p
  end
  local function in_bounds(p)
    return (backward and p > 0) or (not backward and p < #text)
  end
  for _, s in ipairs(self.selections) do
    local endpoint = s.backward and s.start or s.finish
    if (backward and endpoint > 0) or (not backward and endpoint < #text) then
      local cursor = self:head(s)
      local anchor = backward and M.next(text, cursor) or cursor
      local head = backward and cursor or M.next(text, cursor)
      for _ = 1, count do
        if not in_bounds(head) then
          break
        end
        local previous = category(backward and head or M.prev(text, head))
        -- Newline crossings start a selection on the destination line.
        while in_bounds(head) and category(ahead(head)) == -1 do
          previous, head = -1, advance(head)
        end
        if previous == -1 then
          anchor = head
        end
        local start = head
        while in_bounds(head) do
          local current = category(ahead(head))
          local boundary = previous ~= current
            and (
              (backward or ending) and (previous > 0 or current == -1)
              or (not backward and not ending and current ~= 0)
            )
          if boundary then
            if head == start then
              -- A new word replaces the old cursor cell instead of retaining it.
              anchor = head
            else
              break
            end
          end
          previous, head = current, advance(head)
        end
      end
      if self.mode == 'select' then
        local fixed = s.backward and M.prev(text, s.finish) or s.start
        local target = not backward and head > anchor and M.prev(text, head) or head
        s.start, s.finish, s.backward =
          math.min(fixed, target), M.next(text, math.max(fixed, target)), target < fixed or nil
      else
        s.start, s.finish, s.backward =
          math.min(anchor, head), math.max(anchor, head), head < anchor or nil
      end
      s.goal = nil
    end
  end
  self:normalize()
end
function Engine:move(key, count)
  if key:match('^[wWbBeE]$') then
    self:move_word(key, count or 1)
    return
  end
  local text = self.text
  for _, s in ipairs(self.selections) do
    local p = self:head(s)
    local goal = s.goal
    for _ = 1, count or 1 do
      if key == 'h' then
        p = M.prev(text, p)
      elseif key == 'l' then
        p = M.next(text, p)
      elseif key == 'j' or key == 'k' then
        local row = M.position(text, p)
        goal = goal or self:column(p)
        local targetrow = row + (key == 'j' and 1 or -1)
        if targetrow >= 0 then
          local target = self:offset_column(targetrow, goal)
          if M.position(text, target) == targetrow then
            p = target
          end
        end
      elseif key == 'gh' or key == '<Home>' then
        p = line_bounds(text, p)
      elseif key == 'gl' or key == '<End>' then
        local a, b = line_bounds(text, p)
        p = b > a and M.prev(text, b) or a
      elseif key == 'gg' then
        p = 0
      elseif key == 'ge' then
        p = M.prev(text, #text)
      end
    end
    if self.mode == 'select' then
      local anchor = s.backward and M.prev(text, s.finish) or s.start
      local finish = M.next(text, math.max(anchor, p))
      s.start, s.finish, s.backward = math.min(anchor, p), finish, p < anchor or nil
    else
      s.start, s.finish, s.backward = p, M.next(text, p), nil
    end
    s.goal = (key == 'j' or key == 'k') and goal or nil
  end
  self:normalize()
end
local opens = { ['('] = ')', ['['] = ']', ['{'] = '}', ['<'] = '>' }
local closes = { [')'] = '(', [']'] = '[', ['}'] = '{', ['>'] = '<' }
local function delimiters(key, custom)
  assert(type(key) == 'string' and key ~= '', 'Helix surround key must be a nonempty string')
  local open = closes[key] or key
  local pair = custom and (custom[key] or custom[open])
  return pair and pair[1] or open, pair and pair[2] or opens[open] or open
end
local function escaped(text, index)
  local n = 0
  index = index - 1
  while index > 0 and text:sub(index, index) == '\\' do
    n, index = n + 1, index - 1
  end
  return n % 2 == 1
end
local function surrounds(text, key, custom)
  local open, close = delimiters(key, custom)
  local stack, out, p = {}, {}, 0
  while p < #text do
    local nextp = M.next(text, p)
    if not escaped(text, p + 1) then
      if text:sub(p + 1, p + #close) == close and #stack > 0 then
        nextp = p + #close
        out[#out + 1] = { start = table.remove(stack), finish = nextp }
      elseif text:sub(p + 1, p + #open) == open then
        nextp = p + #open
        stack[#stack + 1] = p
      end
    end
    p = nextp
  end
  return out, #open, #close
end
local function enclosing(text, s, key, count, custom)
  local all = {}
  local open, close = delimiters(key, custom)
  if key ~= 'm' and open == close then
    -- Symmetric delimiters surround the cursor, not every other delimiter from
    -- the beginning of the document. This matters for /usr/local/bin and quotes.
    local p = s.backward and s.start or (s.finish > s.start and M.prev(text, s.finish) or s.start)
    local before, after, on_delimiter = {}, {}, false
    local offset = 0
    while offset < #text do
      local nextp = M.next(text, offset)
      if text:sub(offset + 1, offset + #open) == open and not escaped(text, offset + 1) then
        nextp = offset + #open
        if offset <= p and p < nextp then
          on_delimiter = true
        elseif offset < p then
          before[#before + 1] = offset
        elseif offset > p then
          after[#after + 1] = offset
        end
      end
      offset = nextp
    end
    if not on_delimiter then
      local n = count or 1
      local left, right = before[#before - n + 1], after[n]
      if left and right then
        return { start = left, finish = right + #close, left = #open, right = #close }
      end
      return nil
    end
  end
  if key == 'm' then
    local keys, seen = { '(', '[', '{', '<', '"', "'", '`' }, {}
    for alias in pairs(custom or {}) do
      keys[#keys + 1] = alias
    end
    for _, pair in ipairs(keys) do
      local a, b = delimiters(pair, custom)
      local identity = a .. '\0' .. b
      if not seen[identity] then
        seen[identity] = true
        local ranges, left, right = surrounds(text, pair, custom)
        for _, range in ipairs(ranges) do
          range.left, range.right = left, right
          all[#all + 1] = range
        end
      end
    end
  else
    local ranges, left, right = surrounds(text, key, custom)
    for _, range in ipairs(ranges) do
      range.left, range.right = left, right
      all[#all + 1] = range
    end
  end
  local candidates = {}
  for _, range in ipairs(all) do
    if range.start <= s.start and s.finish <= range.finish then
      candidates[#candidates + 1] = range
    end
  end
  table.sort(candidates, function(a, b)
    local alen, blen = a.finish - a.start, b.finish - b.start
    return alen < blen or (alen == blen and a.start > b.start)
  end)
  return candidates[count or 1]
end
function Engine:textobject(key, around, count)
  for _, s in ipairs(self.selections) do
    local p = self:head(s)
    local backward = s.backward
    if key == 'w' or key == 'W' then
      local a, b, cls = p, M.next(self.text, p), class(self.text, p, key == 'W')
      while a > 0 and class(self.text, M.prev(self.text, a), key == 'W') == cls do
        a = M.prev(self.text, a)
      end
      while b < #self.text and class(self.text, b, key == 'W') == cls do
        b = M.next(self.text, b)
      end
      if around then
        local original = b
        while b < #self.text and class(self.text, b, true) == 0 do
          b = M.next(self.text, b)
        end
        if original == b then
          while a > 0 and class(self.text, M.prev(self.text, a), true) == 0 do
            a = M.prev(self.text, a)
          end
        end
      end
      s.start, s.finish = a, b
    elseif key == 'p' then
      local a, _, b = line_bounds(self.text, p)
      while a > 0 do
        local pa, pb = line_bounds(self.text, M.prev(self.text, a))
        if self.text:sub(pa + 1, pb):match('^%s*$') then
          break
        end
        a = pa
      end
      while b < #self.text do
        local _, nb, nextb = line_bounds(self.text, b)
        if self.text:sub(b + 1, nb):match('^%s*$') then
          break
        end
        b = nextb
      end
      if around then
        while b < #self.text do
          local _, nb, nextb = line_bounds(self.text, b)
          if not self.text:sub(b + 1, nb):match('^%s*$') then
            break
          end
          b = nextb
        end
      end
      s.start, s.finish = a, b
    else
      local found = enclosing(self.text, s, key, count, self.surrounds)
      if found then
        s.start, s.finish =
          found.start + (around and 0 or found.left), found.finish - (around and 0 or found.right)
      end
    end
    s.backward, s.goal = (key ~= 'w' and key ~= 'W' and key ~= 'p') and backward or nil, nil
  end
  self:normalize()
end
function Engine:add_cursor(direction)
  local source = self.selections[self.primary]
  local row = M.position(self.text, source.start)
  local erow = M.position(self.text, source.finish)
  local col, ecol = self:column(source.start), self:column(source.finish)
  local targetrow = row + direction
  if targetrow < 0 then
    return
  end
  local a = self:offset_column(targetrow, col)
  if M.position(self.text, a) ~= targetrow then
    return
  end
  local b = self:offset_column(erow + direction, ecol)
  if b == a and source.finish > source.start then
    b = M.next(self.text, a)
  end
  local added = { start = a, finish = math.max(a, b), backward = source.backward }
  self.selections[#self.selections + 1] = added
  self.primary = #self.selections
  self:normalize()
end
function Engine:matches(matcher, split)
  local out = {}
  for _, s in ipairs(self.selections) do
    local text, p, previous = self.text:sub(s.start + 1, s.finish), 0, 0
    while p <= #text do
      local a, b = matcher(text, p)
      if a == nil then
        break
      end
      assert(a >= p and b >= a and b <= #text, 'invalid matcher offsets')
      if split then
        if a > previous then
          out[#out + 1] = { start = s.start + previous, finish = s.start + a }
        end
        previous = b
      elseif b > a then
        out[#out + 1] = { start = s.start + a, finish = s.start + b }
      end
      if b == a then
        if b == #text then
          break
        end
        p = M.next(text, b)
      else
        p = b
      end
    end
    if split and previous < #text then
      out[#out + 1] = { start = s.start + previous, finish = s.finish }
    end
  end
  if #out > 0 then
    self.selections, self.primary = out, 1
    self:normalize()
  end
end
function Engine:find(key, character, count)
  local text = self.text
  for _, s in ipairs(self.selections) do
    local original, p = self:head(s), self:head(s)
    local direction = (key == 'f' or key == 't') and 1 or -1
    local found = true
    for _ = 1, count do
      local match
      if direction == 1 then
        local a = text:find(character, M.next(text, p) + 1, true)
        match = a and a - 1
      else
        local search = 1
        while search <= p do
          local a = text:find(character, search, true)
          if not a or a - 1 >= p then
            break
          end
          match, search = a - 1, a + #character
        end
      end
      if match == nil then
        found = false
        break
      end
      p = match
    end
    if found then
      if key == 't' then
        p = M.prev(text, p)
      elseif key == 'T' then
        p = M.next(text, p)
      end
      local anchor = self.mode == 'select' and (s.backward and M.prev(text, s.finish) or s.start)
        or original
      s.start, s.finish, s.backward =
        math.min(anchor, p), M.next(text, math.max(anchor, p)), p < anchor or nil
      s.goal = nil
    end
  end
  self:normalize()
end
function Engine:surround(key)
  local open, close = delimiters(key, self.surrounds)
  local values = {}
  for i, s in ipairs(self.selections) do
    values[i] = open .. self.text:sub(s.start + 1, s.finish) .. close
  end
  self:replace(values)
end
function Engine:change_surround(key, replacement, count)
  local open, close = '', ''
  if replacement then
    open, close = delimiters(replacement, self.surrounds)
  end
  local edits = {}
  for _, s in ipairs(self.selections) do
    local found = enclosing(self.text, s, key, count, self.surrounds)
    if not found then
      return false
    end
    edits[#edits + 1] = { start = found.start, finish = found.start + found.left, value = open }
    edits[#edits + 1] = { start = found.finish - found.right, finish = found.finish, value = close }
  end
  table.sort(edits, function(a, b)
    return a.start < b.start
  end)
  local ranges, values = {}, {}
  for _, edit in ipairs(edits) do
    local last = ranges[#ranges]
    if last and edit.start == last.start and edit.finish == last.finish then
      -- Multiple cursors can share a surround; edit each delimiter only once.
      if edit.value ~= last.value then
        return false
      end
    elseif last and edit.start < last.finish then
      return false
    else
      edit.delta = (last and last.delta or 0) + #edit.value - (edit.finish - edit.start)
      ranges[#ranges + 1], values[#values + 1] = edit, edit.value
    end
  end
  local function mapped(position, right)
    local low, high = 1, #ranges
    while low <= high do
      local middle = math.floor((low + high) / 2)
      if ranges[middle].finish <= position then
        low = middle + 1
      else
        high = middle - 1
      end
    end
    local delta = high > 0 and ranges[high].delta or 0
    local edit = ranges[low]
    if edit and position > edit.start then
      return edit.start + delta + (right and #edit.value or 0)
    end
    return position + delta
  end
  local selections, primary = copy(self.selections), self.primary
  self:replace(values, false, ranges)
  -- Only delimiters change. Retain the original content, direction and primary
  -- selection, mapping endpoints inside a delimiter onto its replacement.
  for _, s in ipairs(selections) do
    s.start, s.finish, s.goal = mapped(s.start, false), mapped(s.finish, true), nil
  end
  self.selections, self.primary, self.mode = selections, primary, 'normal'
  self:normalize()
  return true
end
function Engine:line_insert(key)
  self.mode = 'insert'
  local ranges = {}
  for i, s in ipairs(self.selections) do
    local a, b = line_bounds(self.text, self:head(s))
    local p = (key == 'A' or key == 'o') and b or a
    if key == 'I' then
      local whitespace = self.text:sub(a + 1, b):match('^%s*')
      p = a + #whitespace
    end
    ranges[i] = { start = p, finish = p }
  end
  -- Cursors on the same line share an insertion point.
  local old = self.selections
  self.selections = ranges
  self:normalize()
  ranges = copy(self.selections)
  self.selections = old
  local value = (key == 'o' or key == 'O') and '\n' or ''
  self:replace(value, true, ranges)
  if key == 'O' then
    for _, s in ipairs(self.selections) do
      s.start, s.finish = s.start - 1, s.finish - 1
    end
  end
end
function Engine:input(key)
  if key == '<Esc>' or key == '<C-c>' then
    if self.mode == 'insert' then
      for _, s in ipairs(self.selections) do
        s.start = M.prev(self.text, s.start)
        s.finish = M.next(self.text, s.start)
      end
    end
    self.mode, self.pending, self.count = 'normal', '', ''
    self:normalize()
    return
  end
  local arrows = { ['<Left>'] = 'h', ['<Right>'] = 'l', ['<Up>'] = 'k', ['<Down>'] = 'j' }
  if self.mode == 'insert' then
    if key == '<BS>' or key == '<C-h>' then
      self:backspace(false)
    elseif key == '<C-w>' then
      self:backspace(false, true)
    elseif key == '<Del>' then
      self:backspace(true)
    elseif key == '<CR>' or key == '<C-j>' then
      self:replace('\n', true)
    elseif key == '<Tab>' then
      self:replace('\t', true)
    elseif arrows[key] or key == '<Home>' or key == '<End>' then
      -- Move insertion points without leaving insert mode.
      if key == '<Home>' or key == '<End>' then
        for _, s in ipairs(self.selections) do
          local a, b = line_bounds(self.text, s.start)
          local p = key == '<Home>' and a or b
          s.start, s.finish = p, p
        end
      else
        for _, s in ipairs(self.selections) do
          s.finish = s.start
        end
        self:move(arrows[key], 1)
        for _, s in ipairs(self.selections) do
          local p = self:head(s)
          s.start, s.finish = p, p
        end
      end
    elseif key:sub(1, 1) ~= '<' or #key == 1 then
      self:replace(key, true)
    end
    return
  end
  local count = math.min(tonumber(self.count) or 1, 10000)
  local literal = key:sub(1, 1) ~= '<' or #key == 1
  if self.pending == 'mi' or self.pending == 'ma' then
    self:textobject(key, self.pending == 'ma', count)
  elseif self.pending == 'ms' then
    if literal then
      self:surround(key)
    end
  elseif self.pending == 'mr' then
    if literal then
      self.pending = 'mr' .. key
      return
    end
  elseif self.pending:sub(1, 2) == 'mr' then
    if literal then
      self:change_surround(self.pending:sub(3), key, count)
    end
  elseif self.pending == 'md' then
    if literal then
      self:change_surround(key, nil, count)
    end
  elseif self.pending == 'm' then
    if key == 'i' or key == 'a' or key == 's' or key == 'r' or key == 'd' then
      self.pending = 'm' .. key
      return
    end
  elseif self.pending == 'g' then
    self:move('g' .. key, count)
  elseif self.pending:match('^[fFtT]$') then
    self:find(self.pending, key, count)
  elseif self.pending == 'r' then
    if literal then
      local values = {}
      for i, s in ipairs(self.selections) do
        local p, n = s.start, 0
        while p < s.finish do
          p, n = M.next(self.text, p), n + 1
        end
        values[i] = key:rep(n)
      end
      self:replace(values)
    end
  elseif self.pending ~= '' then
    -- Unknown prefixes are canceled; they never become native Vim operators.
  else
    if key:match('^%d$') then
      self.count = tostring(math.min((tonumber(self.count) or 0) * 10 + tonumber(key), 10000))
      return
    end
    if key == 'm' or key == 'g' or key == 'r' or key:match('^[fFtT]$') then
      self.pending = key
      return
    end
    key = arrows[key] or key
    if key:match('^[hjklwWbBeE]$') or key == '<Home>' or key == '<End>' then
      self:move(key, count)
    elseif key == 'v' then
      self.mode = self.mode == 'select' and 'normal' or 'select'
    elseif key == 'i' or key == 'a' or key == 'c' then
      self:insert(key == 'a', key == 'c')
    elseif key == 'I' or key == 'A' or key == 'o' or key == 'O' then
      self:line_insert(key)
    elseif key == 'd' then
      self:yank()
      self:replace('')
    elseif key == 'y' then
      self:yank()
    elseif key == 'p' or key == 'P' then
      if #self.register > 0 then
        local ranges = {}
        for i, s in ipairs(self.selections) do
          local p = key == 'p' and s.finish or s.start
          ranges[i] = { start = p, finish = p }
        end
        self:replace(self:paste_values(), false, ranges)
      end
    elseif key == 'R' then
      if #self.register > 0 then
        self:replace(self:paste_values())
      end
    elseif key == 'C' or key == '<A-C>' or key == '<M-C>' then
      for _ = 1, count do
        self:add_cursor(key == 'C' and 1 or -1)
      end
    elseif key == ',' then
      self.selections, self.primary = { self.selections[self.primary] }, 1
    elseif key == '<A-,>' or key == '<M-,>' then
      if #self.selections > 1 then
        table.remove(self.selections, self.primary)
        self.primary = math.min(self.primary, #self.selections)
      end
    elseif key == ';' then
      for _, s in ipairs(self.selections) do
        local p = self:head(s)
        s.start, s.finish, s.backward = p, M.next(self.text, p), nil
      end
    elseif key == '<A-;>' or key == '<M-;>' then
      for _, s in ipairs(self.selections) do
        s.backward = not s.backward or nil
      end
    elseif key == '(' or key == ')' then
      self.primary = (self.primary - 1 + (key == ')' and count or -count)) % #self.selections + 1
    elseif key == '%' then
      self.selections, self.primary = { { start = 0, finish = #self.text } }, 1
    elseif key == 'x' then
      for _, s in ipairs(self.selections) do
        local a = line_bounds(self.text, s.start)
        local _, _, b = line_bounds(self.text, self:head(s))
        for _ = 1, count do
          if s.start == a and s.finish == b and b < #self.text then
            local _, _, nextb = line_bounds(self.text, b)
            b = nextb
          end
          s.start, s.finish = a, b
        end
        s.backward, s.goal = nil, nil
      end
      self:normalize()
    elseif key == 's' or key == 'S' then
      self.count = ''
      return key == 's' and 'select_regex' or 'split_regex'
    elseif key == '<A-s>' or key == '<M-s>' then
      self:matches(function(text, p)
        local a = text:find('\n', p + 1, true)
        if a then
          return a - 1, a
        end
      end, true)
    elseif key == '~' or key == '`' or key == '<A-`>' or key == '<M-`>' then
      local values = {}
      for i, s in ipairs(self.selections) do
        local value = self.text:sub(s.start + 1, s.finish)
        if key == '~' then
          local characters = vim.fn.split(value, [[\zs]])
          for j, c in ipairs(characters) do
            local lower = vim.fn.tolower(c)
            characters[j] = c == lower and vim.fn.toupper(c) or lower
          end
          value = table.concat(characters)
        elseif key == '`' then
          value = vim.fn.tolower(value)
        else
          value = vim.fn.toupper(value)
        end
        values[i] = value
      end
      self:replace(values)
    end
  end
  self.pending, self.count = '', ''
end
function Engine:validate()
  assert(#self.selections > 0 and self.primary >= 1 and self.primary <= #self.selections)
  local finish = -1
  for _, s in ipairs(self.selections) do
    assert(s.start >= 0 and s.start <= s.finish and s.finish <= #self.text)
    assert(
      M.boundary(self.text, s.start) == s.start and M.boundary(self.text, s.finish) == s.finish
    )
    assert(s.start >= finish, 'overlapping selections')
    finish = s.finish
  end
  return true
end
return M
