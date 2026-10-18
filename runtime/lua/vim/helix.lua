--- Native selection-first editing. Enable with vim.o.helix = true.
--- Core owns selections and undo; these commands calculate transformations
--- against a temporary snapshot and submit native editing transactions.
local api = vim.api
local commands = require('vim.helix.commands')
local M = {}
local parsers = {}
local registers = {}
local last_search
local configuration = { surrounds = {} }

--- @private
function M._pending_argument()
  local parser = parsers[api.nvim_get_current_win()]
  return parser ~= nil and parser.buffer == api.nvim_get_current_buf() and parser.pending ~= ''
end

--- @class vim.helix.Opts
--- @field enabled? boolean Enable the mode (default true).
--- @field surrounds? table<string, [string, string]> Custom {open, close} pairs.
--- @field keymaps? table<string, string|function|false> Overrides in the h namespace.

--- Enable native Helix editing with optional command configuration.
--- Built-in commands/pairs require no entries. Supplied surrounds replace the
--- previous custom registry; mappings update only the supplied keys.
--- @param opts? vim.helix.Opts
function M.setup(opts)
  if opts == nil then
    opts = {}
  end
  vim.validate('opts', opts, 'table')
  vim.validate('enabled', opts.enabled, 'boolean', true)
  vim.validate('surrounds', opts.surrounds, 'table', true)
  vim.validate('keymaps', opts.keymaps, 'table', true)
  for key in pairs(opts) do
    assert(
      key == 'enabled' or key == 'surrounds' or key == 'keymaps',
      'Unknown Helix option: ' .. tostring(key)
    )
  end
  for key, pair in pairs(opts.surrounds or {}) do
    assert(
      type(key) == 'string'
        and vim.fn.strchars(key) == 1
        and not key:find('[%c]')
        and not key:match('^[mwWp]$'),
      'Helix surround keys must be one character other than m, w, W or p'
    )
    assert(
      type(pair) == 'table' and vim.islist(pair) and #pair == 2,
      'Expected a Helix {open, close} pair'
    )
    for _, delimiter in ipairs(pair) do
      assert(
        type(delimiter) == 'string' and delimiter ~= '' and not delimiter:find('[%z\r\n]'),
        'Helix delimiters must be nonempty single-line strings without NUL'
      )
    end
  end
  for lhs, rhs in pairs(opts.keymaps or {}) do
    assert(type(lhs) == 'string' and lhs ~= '', 'Helix mapping keys must be nonempty strings')
    assert(
      type(rhs) == 'string' or type(rhs) == 'function' or rhs == false,
      'Helix mappings require a string, function or false'
    )
  end
  if opts.surrounds then
    configuration.surrounds = vim.deepcopy(opts.surrounds)
  end
  for lhs, rhs in pairs(opts.keymaps or {}) do
    vim.keymap.set('h', lhs, rhs == false and '<Nop>' or rhs, { silent = true })
  end
  parsers = {}
  vim.o.helix = opts.enabled ~= false
end

local function name(key)
  key = key:gsub('^<C%-(%u)>$', function(c)
    return '<C-' .. c:lower() .. '>'
  end)
  if key == '<Space>' then
    return ' '
  end
  if key == '<lt>' then
    return '<'
  end
  if key == '<Return>' or key == '<Enter>' then
    return '<CR>'
  end
  return key
end

local function buffer_text()
  return table.concat(api.nvim_buf_get_lines(0, 0, -1, true), '\n')
end

local function model(insert)
  local state = api.nvim_helix_get_state(0)
  local text = buffer_text()
  local e = commands.new(text, 0, {
    display_width = vim.fn.strdisplaywidth,
    surrounds = configuration.surrounds,
  })
  local win = api.nvim_get_current_win()
  local parser = parsers[win] or { pending = '', count = '' }
  if parser.buffer ~= api.nvim_get_current_buf() then
    parser = { pending = '', count = '', buffer = api.nvim_get_current_buf() }
  end
  parsers[win] = parser
  e.mode = insert and 'insert' or state.extending and 'select' or 'normal'
  local register_name = parser.register_name or '"'
  local native_value = vim.fn.getreg(register_name)
  local saved = registers[register_name]
  e.pending, e.count = parser.pending, parser.count
  e.register = saved and saved.text == native_value and saved.values or { native_value }
  e.selections, e.primary = {}, state.primary
  local restore_goals = parser.selections and vim.deep_equal(state.selections, parser.selections)
  for i, s in ipairs(state.selections) do
    e.selections[#e.selections + 1] = {
      start = commands.offset(text, s[1], s[2]),
      finish = commands.offset(text, s[3], s[4]),
      backward = s[5] or nil,
      goal = restore_goals and parser.goals[i] or nil,
    }
  end
  e:normalize()
  local batches = {}
  e.on_edit = function(edits, source)
    local batch = {}
    for _, edit in ipairs(edits) do
      if source:sub(edit.start + 1, edit.finish) ~= edit.value then
        local sr, sc = commands.position(source, edit.start)
        local er, ec = commands.position(source, edit.finish)
        batch[#batch + 1] = { sr, sc, er, ec, vim.split(edit.value, '\n', { plain = true }) }
      end
    end
    if #batch > 10000 then
      -- Apply later chunks first so all coordinates refer to this snapshot.
      -- commit() joins these native calls into one undo step.
      for last = #batch, 1, -10000 do
        local chunk = {}
        for i = math.max(1, last - 9999), last do
          chunk[#chunk + 1] = batch[i]
        end
        batches[#batches + 1] = chunk
      end
    elseif #batch > 0 then
      batches[#batches + 1] = batch
    end
  end
  return e, parser, batches
end

local function commit(e, parser, batches, insert)
  for i, batch in ipairs(batches) do
    api.nvim_helix_apply_edits(batch, insert or i > 1)
  end
  local selections = {}
  for _, s in ipairs(e.selections) do
    local sr, sc = commands.position(e.text, s.start)
    local er, ec = commands.position(e.text, s.finish)
    selections[#selections + 1] = { sr, sc, er, ec, s.backward or false }
  end
  api.nvim_helix_set_selections(0, selections, e.primary, e.mode == 'select')
  parser.pending, parser.count = e.pending, e.count
  parser.selections, parser.goals = selections, {}
  for i, s in ipairs(e.selections) do
    parser.goals[i] = s.goal or false
  end
  local register_name = parser.register_name or '"'
  if register_name ~= '_' and not register_name:match('%u') then
    registers[register_name] = { values = e.register, text = vim.fn.getreg(register_name) }
  end
end

--- InsertCharPre may replace one typed character with arbitrary text. Core
--- invokes it once per input, then applies its result to every insertion gap.
--- @private
function M._insert_text(text)
  local e, parser, batches = model(true)
  e:replace(text, true)
  commit(e, parser, batches, true)
end

local function regex_matches(e, pattern, split)
  vim.regex(pattern) -- Validate before modifying selections.
  e:matches(function(text, offset)
    local found = vim.fn.matchstrpos(text, pattern, offset, 1)
    if found[2] >= 0 then
      return found[2], found[3]
    end
  end, split)
end

--- Select regex matches within the current selections.
--- @param pattern string Vim regular expression.
--- @param split? boolean Select pieces separated by matches instead.
function M.select(pattern, split)
  local e, parser, batches = model(false)
  regex_matches(e, pattern, split)
  commit(e, parser, batches, false)
end

--- Select text inside/around a delimiter, word or closest surround (`m`).
--- @param object string For example 'm', '/', '(', 'w'.
--- @param around? boolean Include delimiters.
--- @param count? integer Select the nth enclosing object.
function M.textobject(object, around, count)
  local e, parser, batches = model(false)
  e:textobject(object, around or false, count or 1)
  commit(e, parser, batches, false)
end

--- Surround every selection using a built-in delimiter or configured key.
--- @param key string For example '(', '"', or a custom surround key.
function M.surround(key)
  local e, parser, batches = model(false)
  e:surround(key)
  commit(e, parser, batches, false)
end

--- Replace surrounds at every selection, retaining the selected content.
--- @param from string Existing pair key, or 'm' for the closest surround.
--- @param to string New built-in or configured pair key.
--- @param count? integer Select the nth enclosing pair (default 1).
function M.replace_surround(from, to, count)
  vim.validate('to', to, 'string')
  local e, parser, batches = model(false)
  e:change_surround(from, to, count or 1)
  commit(e, parser, batches, false)
end

--- Delete surrounds at every selection, retaining the selected content.
--- @param key string Existing pair key, or 'm' for the closest surround.
--- @param count? integer Select the nth enclosing pair (default 1).
function M.delete_surround(key, count)
  local e, parser, batches = model(false)
  e:change_surround(key, nil, count or 1)
  commit(e, parser, batches, false)
end

--- Search the buffer with a Vim regex, selecting the next/previous match at
--- each cursor. Repetition wraps at EOF; zero-width matches are skipped.
--- @param pattern string
--- @param backward? boolean
--- @param count? integer
function M.search(pattern, backward, count)
  vim.regex(pattern)
  local e, parser, batches = model(false)
  local matches, offset = {}, 0
  while offset <= #e.text do
    local found = vim.fn.matchstrpos(e.text, pattern, offset, 1)
    local a, b = found[2], found[3]
    if a < 0 then
      break
    end
    if b > a then
      matches[#matches + 1] = { start = a, finish = b }
    end
    if b > offset then
      offset = b
    elseif offset < #e.text then
      offset = commands.next(e.text, offset)
    else
      break
    end
  end
  if #matches > 0 then
    for _, selection in ipairs(e.selections) do
      local head = e:head(selection)
      local target
      if backward then
        for i = #matches, 1, -1 do
          if matches[i].start < selection.start then
            target = i
            break
          end
        end
        target = target or #matches
      else
        for i, match in ipairs(matches) do
          if match.start > head then
            target = i
            break
          end
        end
        target = target or 1
      end
      target = ((target - 1 + (backward and -1 or 1) * ((count or 1) - 1)) % #matches) + 1
      local match = matches[target]
      if e.mode == 'select' then
        local anchor = selection.backward and commands.prev(e.text, selection.finish)
          or selection.start
        local endpoint = backward and match.start or commands.prev(e.text, match.finish)
        selection.start = math.min(anchor, endpoint)
        selection.finish = commands.next(e.text, math.max(anchor, endpoint))
        selection.backward = endpoint < anchor or nil
      else
        selection.start, selection.finish, selection.backward = match.start, match.finish, nil
      end
      selection.goal = nil
    end
    e:normalize()
  end
  last_search = { pattern = pattern, backward = backward or false }
  vim.fn.setreg('/', pattern)
  commit(e, parser, batches, false)
end

--- Get native state, including parser information for a statusline.
function M.get_state()
  local state = api.nvim_helix_get_state(0)
  local parser = parsers[api.nvim_get_current_win()]
  state.pending = parser and parser.pending or ''
  state.count = parser and parser.count or ''
  return state
end

function M.statusline()
  if not vim.o.helix then
    return ''
  end
  local state = M.get_state()
  if not state.enabled then
    return ''
  end
  local mode = api.nvim_get_mode().mode
  return ('HELIX %s [%d] %s%s'):format(
    mode:sub(1, 1) == 'i' and 'INSERT' or state.extending and 'SELECT' or 'NORMAL',
    #state.selections,
    state.count,
    state.pending
  )
end

local function insert_newline(e)
  local values = {}
  local width = vim.bo.shiftwidth == 0 and vim.bo.tabstop or vim.bo.shiftwidth
  local unit = vim.bo.expandtab and (' '):rep(width) or '\t'
  for i, s in ipairs(e.selections) do
    local row = commands.position(e.text, s.start)
    local first = commands.offset(e.text, row, 0)
    local before = e.text:sub(first + 1, s.start)
    local indent = (vim.bo.autoindent or vim.bo.smartindent or vim.bo.cindent)
        and (before:match('^[ \t]*') or '')
      or ''
    if vim.bo.smartindent and before:match('[{:]%s*$') then
      indent = indent .. unit
    end
    values[i] = '\n' .. indent
  end
  e:replace(values, true)
end

--- Core input entry point. Unlike vim.on_key this runs after native Helix
--- mappings, outside textlock, without consuming or replaying Vim operators.
--- @private
function M._dispatch(key, insert)
  key = name(key)
  local e, parser, batches = model(insert)
  if not insert and parser.pending == 'register' then
    parser.register_name = key:match('^[%w"*+%-%_]$') and key or nil
    parser.pending = ''
    return
  end
  if not insert and e.pending == '' then
    if key == '"' then
      parser.pending = 'register'
      return
    elseif key == '/' or key == '?' then
      local count = tonumber(e.count) or 1
      parser.count = ''
      local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      vim.ui.input({ prompt = key }, function(pattern)
        if
          pattern
          and pattern ~= ''
          and api.nvim_get_current_win() == win
          and api.nvim_get_current_buf() == buf
        then
          local ok, err = pcall(M.search, pattern, key == '?', count)
          if not ok then
            vim.notify(tostring(err), vim.log.levels.ERROR)
          end
        end
      end)
      return
    elseif key == 'n' or key == 'N' then
      if last_search then
        local count = tonumber(e.count) or 1
        parser.count = ''
        local original = last_search
        local backward = original.backward
        if key == 'N' then
          backward = not backward
        end
        M.search(original.pattern, backward, count)
        last_search = original
      end
      return
    elseif key == '*' then
      local s = e.selections[e.primary]
      local value = e.text:sub(s.start + 1, s.finish)
      if value ~= '' then
        M.search([[\V]] .. value:gsub('\\', '\\\\'), false)
      end
      return
    elseif key == ':' or key == '<C-w>' or key == '<C-l>' then
      parser.count = ''
      return 'native'
    elseif key == 'u' or key == 'U' then
      local count = math.min(tonumber(e.count) or 1, 10000)
      parser.pending, parser.count = '', ''
      for _ = 1, count do
        vim.cmd(key == 'u' and 'undo' or 'redo')
      end
      return
    end
  end
  local original_register = e.register
  local register_name = parser.register_name or '"'
  local action
  if insert and (key == '<CR>' or key == '<C-j>') then
    insert_newline(e)
  elseif insert and key == '<Tab>' and vim.bo.expandtab then
    local values = {}
    for i, s in ipairs(e.selections) do
      values[i] = (' '):rep(vim.bo.tabstop - e:column(s.start) % vim.bo.tabstop)
    end
    e:replace(values, true)
  else
    action = e:input(key)
  end
  commit(e, parser, batches, insert)
  if e.register ~= original_register and #e.register > 0 then
    vim.fn.setreg(register_name, table.concat(e.register, '\n'), 'v')
    if register_name ~= '_' and not register_name:match('%u') then
      registers[register_name] = { values = e.register, text = vim.fn.getreg(register_name) }
    end
  end
  if e.pending == '' and e.count == '' then
    parser.register_name = nil
  end
  if action == 'select_regex' or action == 'split_regex' then
    local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
    vim.ui.input(
      { prompt = action == 'select_regex' and 'Select: ' or 'Split: ' },
      function(pattern)
        if pattern and api.nvim_get_current_win() == win and api.nvim_get_current_buf() == buf then
          local ok, err = pcall(M.select, pattern, action == 'split_regex')
          if not ok then
            vim.notify(tostring(err), vim.log.levels.ERROR)
          end
        end
      end
    )
  end
  if not insert and e.mode == 'insert' then
    return 'insert'
  end
end

--- Format current selections explicitly rather than relying on Vim Visual mode.
function M.format(opts)
  opts = vim.tbl_extend('force', {}, opts or {})
  local ranges = {}
  for _, s in ipairs(api.nvim_helix_get_state(0).selections) do
    ranges[#ranges + 1] = { start = { s[1] + 1, s[2] }, ['end'] = { s[3] + 1, s[4] } }
  end
  opts.range = #ranges == 1 and ranges[1] or ranges
  vim.lsp.buf.format(opts)
end

for group, link in pairs({ HelixSelection = 'Visual', HelixCursor = 'Cursor' }) do
  api.nvim_set_hl(0, group, { default = true, link = link })
end
local group = api.nvim_create_augroup('nvim.helix', { clear = true })
api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
  group = group,
  callback = function()
    parsers[api.nvim_get_current_win()] = nil
  end,
})
api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(ev)
    parsers[tonumber(ev.match)] = nil
  end,
})
api.nvim_create_autocmd('OptionSet', {
  group = group,
  pattern = 'helix',
  callback = function()
    parsers = {}
  end,
})

-- Bracketed paste has one transaction and one value per selection. Preserve
-- the existing paste handler for ordinary Neovim and special plugin buffers.
local native_paste = vim.paste
local paste_chunks
local paste_target
vim.paste = function(lines, phase)
  local target = { api.nvim_get_current_win(), api.nvim_get_current_buf() }
  if paste_chunks and (not vim.o.helix or not vim.deep_equal(target, paste_target)) then
    paste_chunks, paste_target = nil, nil
    return false
  end
  if not vim.o.helix or not api.nvim_helix_get_state(0).enabled then
    return native_paste(lines, phase)
  end
  local state = api.nvim_helix_get_state(0)
  local mode = api.nvim_get_mode().mode
  if
    not (
      mode == 'n'
      or mode:sub(1, 1) == 'h'
      or (mode:sub(1, 1) == 'i' and state.inserting and vim.fn.pumvisible() == 0)
    )
  then
    return native_paste(lines, phase)
  end
  if phase == -1 or phase == 1 then
    paste_chunks, paste_target = {}, target
  end
  paste_chunks = paste_chunks or {}
  paste_chunks[#paste_chunks + 1] = table.concat(lines, '\n')
  if phase == -1 or phase == 3 then
    local e, parser, batches = model(state.inserting)
    local value = table.concat(paste_chunks)
    paste_chunks, paste_target = nil, nil
    e:replace(value, state.inserting)
    commit(e, parser, batches, state.inserting)
  end
  return true
end

return M
