-- Real plugin workflows in an isolated, attached UI. No user config is loaded.
-- With a plugin directory argument this is offline; otherwise fetch exact pins.
-- Run: exon --headless -u NONE -i NONE -l contrib/helix/plugin-smoke.lua [plugins]
local source = vim.fs.dirname(vim.fs.abspath(arg[0]))
local pins = vim.json.decode(table.concat(vim.fn.readfile(source .. '/plugins.json'), '\n'))
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, 'p')
local root = arg[1] or temporary .. '/plugins'
local function git(args)
  local result = vim.system(vim.list_extend({ 'git' }, args), { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
for name, pin in pairs(pins) do
  local path = root .. '/' .. name
  if not arg[1] then
    vim.fn.mkdir(path, 'p')
    git({ 'init', '-q', path })
    git({ '-C', path, 'fetch', '-q', '--depth=1', pin.src, pin.rev })
    git({ '-C', path, 'checkout', '-q', '--detach', 'FETCH_HEAD' })
  end
  assert(git({ '-C', path, 'rev-parse', 'HEAD' }) == pin.rev, name .. ': unexpected revision')
end
print('Pinned plugin revisions verified')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-u', 'NONE', '-i', 'NONE', '-n' }, {
  rpc = true,
  env = {
    XDG_CONFIG_HOME = temporary .. '/config',
    XDG_STATE_HOME = temporary .. '/state',
    XDG_CACHE_HOME = temporary .. '/cache',
    XDG_DATA_HOME = temporary .. '/data',
    NVIM_LOG_FILE = temporary .. '/nvim.log',
  },
})
assert(child > 0)
local deadline = vim.defer_fn(function()
  vim.fn.jobstop(child)
end, 45000)
local function r(method, ...)
  return vim.rpcrequest(child, method, ...)
end
local function e(code, args)
  local mode = r('nvim_get_mode')
  if mode.blocking and mode.mode:sub(1, 1) == 'r' then
    r('nvim_input', '<CR>')
    error('Unexpected prompt: ' .. r('nvim_exec2', 'messages', { output = true }).output)
  end
  return r('nvim_exec_lua', code, args or {})
end
local function input(keys)
  r('nvim_input', keys)
end
local function wait_for(code, message)
  assert(
    vim.wait(5000, function()
      return e(code)
    end, 20),
    message
  )
end
local ok, err = xpcall(function()
  r('nvim_ui_attach', 100, 32, { rgb = true })
  e(
    [[
    local root,pins=...
    for name in pairs(pins) do vim.opt.runtimepath:append(root..'/'..name) end
    vim.g.mapleader=' '
    vim.o.helix=true
    vim.o.timeoutlen=500
    require('flash').setup({})
    vim.keymap.set('h','s',function() require('flash').jump() end,{desc='Flash'})
    require('telescope').setup({extensions={['ui-select']={
      require('telescope.themes').get_dropdown({previewer=false,
        mappings={i={['<Esc>']=require('telescope.actions').close}}})
    }}})
    require('telescope').load_extension('ui-select')
    vim.keymap.set('h','<Space>ff',require('telescope.builtin').find_files,{desc='Find files'})
    require('which-key').setup(vim.helix.compat.which_key({delay=0,icons={mappings=false},
      spec={{'<Space>f',group='Files',mode='h'}}}))
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha beta gamma','delta beta epsilon','zeta beta theta'})
  ]],
    { root, pins }
  )
  print('Plugin setup complete')
  wait_for(
    [[return require('which-key.config').loaded==true and vim.fn.maparg(' ','h',false,true).desc=='which-key-trigger']],
    'which-key did not register Helix triggers'
  )
  e([[vim.api.nvim_helix_set_selections(0,{{0,0,0,5,false},{1,0,1,5,true}},2,true)]])
  local original = e([[local s=vim.helix.get_state(); return {s.selections,s.primary,s.extending}]])
  input(' ')
  wait_for([[return require('which-key.view').valid()==true]], 'which-key did not open in hv mode')
  input('<Esc>')
  wait_for([[return not require('which-key.view').valid()]], 'which-key did not close')
  assert(
    vim.deep_equal(
      original,
      e([[local s=vim.helix.get_state(); return {s.selections,s.primary,s.extending}]])
    ),
    'which-key cancellation changed selections'
  )
  input('<Esc> ff')
  print('which-key selection cancellation passed')
  wait_for(
    [[return vim.bo.filetype=='TelescopePrompt']],
    'fast which-key sequence did not open Telescope'
  )
  input('<Esc><Esc>')
  wait_for([[return vim.fn.mode()=='h']], 'Telescope did not return to Helix mode')
  print('Fast Telescope shortcut passed')
  input(' ')
  wait_for([[return require('which-key.view').valid()==true]], 'which-key root did not reopen')
  input('f')
  wait_for(
    [[local s=require('which-key.state').state; return s and s.node.keys=='<Space>f']],
    'Files submenu did not open'
  )
  input('f')
  wait_for(
    [[return vim.bo.filetype=='TelescopePrompt']],
    'slow which-key sequence did not open Telescope'
  )
  input('<Esc><Esc>')
  wait_for([[return vim.fn.mode()=='h']], 'picker cancellation left wrong mode')
  print('Slow Telescope shortcut passed')
  e([[
    vim.keymap.set('h','<F8>',function()
      vim.ui.select({'first','second'},{prompt='Code action test'},function(item) vim.g.chosen_action=item end)
    end)
  ]])
  input('<F8>')
  wait_for(
    [[
    if vim.bo.filetype~='TelescopePrompt' then return false end
    local picker=require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker and picker.manager and picker.manager:num_results()==2
      and require('telescope.actions.state').get_selected_entry()~=nil
  ]],
    'ui-select did not populate Telescope'
  )
  input('<CR>')
  wait_for(
    [[return vim.g.chosen_action=='first' and vim.fn.mode()=='h']],
    'ui-select did not choose and return to Helix'
  )
  input('sbeta')
  print('Telescope ui-select passed')
  wait_for(
    [[
    for state in pairs(require('flash.state')._states) do
      if state.visible and state.pattern.pattern=='beta' then
        for _,match in ipairs(state.results) do
          if match.pos[1]==2 and match.pos[2]==6 and type(match.label)=='string' then return true end
        end
      end
    end
    return false
  ]],
    'Flash did not label visible text'
  )
  local label = e([[
    for state in pairs(require('flash.state')._states) do
      if state.visible then
        for _,match in ipairs(state.results) do
          if match.pos[1]==2 and match.pos[2]==6 then return match.label end
        end
      end
    end
  ]])
  input(label)
  wait_for([[return vim.deep_equal(vim.api.nvim_win_get_cursor(0),{2,6})]], 'Flash did not jump')
  input('<Esc>')
  e([[
    vim.diagnostic.set(vim.api.nvim_create_namespace('plugin-baseline'),0,{
      {lnum=0,col=0,message='first'}, {lnum=2,col=0,message='last'},
    })
  ]])
  input(']d')
  wait_for(
    [[return vim.api.nvim_win_get_cursor(0)[1]==3]],
    'diagnostic default failed with plugins active'
  )
  assert(e([[return #require('which-key.config').issues]]) == 0, 'which-key configuration issues')
  assert(e([[return vim.v.errmsg]]) == '', 'editor reported an error')
  print('PASS: which-key h/hv, fast/slow shortcuts, Telescope, ui-select, Flash, diagnostics')
end, debug.traceback)
if not ok then
  pcall(function()
    print(
      vim.inspect(
        e(
          [[return {mode=vim.fn.mode(true),messages=vim.api.nvim_exec2('messages',{output=true}).output}]]
        )
      )
    )
  end)
end
pcall(r, 'nvim_command', 'qa!')
deadline:stop()
deadline:close()
vim.fn.jobwait({ child }, 1000)
vim.fn.delete(temporary, 'rf')
assert(ok, err)
