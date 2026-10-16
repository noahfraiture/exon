-- Exercise the installed executable and runtime through real msgpack RPC.
-- Uses a temporary Neovim state directory and never reads the user's init.lua.
local binary = arg[1] or vim.v.progpath
local config = arg[2]
local temporary = vim.fn.tempname()
local child = vim.fn.jobstart(
  { binary, '--headless', '--embed', '-i', 'NONE', '-u', config or 'NONE' },
  {
    rpc = true,
    env = {
      VIMRUNTIME = '', -- Locate the runtime relative to the installed executable.
      XDG_CONFIG_HOME = temporary .. '/config',
      XDG_DATA_HOME = temporary .. '/data',
      XDG_STATE_HOME = temporary .. '/state',
      XDG_CACHE_HOME = temporary .. '/cache',
      NVIM_LOG_FILE = temporary .. '/nvim.log',
    },
  }
)
assert(child > 0, 'failed to start installed Neovim')
local function request(method, ...)
  return vim.rpcrequest(child, method, ...)
end
local function input(keys)
  request('nvim_input', keys)
end
local function wait_for(check)
  assert(vim.wait(3000, check, 10), 'installed Helix smoke check timed out')
end
local ok, err = xpcall(function()
  request('nvim_set_option_value', 'helix', true, {})
  wait_for(function()
    return request('nvim_get_mode').mode == 'h'
  end)
  request(
    'nvim_exec_lua',
    [[
    vim.helix.setup({
      surrounds = {c = {'/*', '*/'}},
      keymaps = {['<F6>'] = 'msc'},
    })
  ]],
    {}
  )
  request('nvim_buf_set_lines', 0, 0, -1, true, { 'outer([hello])' })
  request('nvim_win_set_cursor', 0, { 1, 8 })
  input('mimcworld<Esc>')
  wait_for(function()
    return request('nvim_get_current_line') == 'outer([world])'
  end)
  input('u')
  wait_for(function()
    return request('nvim_get_current_line') == 'outer([hello])'
  end)
  request('nvim_buf_set_lines', 0, 0, -1, true, { 'one', 'two' })
  request('nvim_helix_set_selections', 0, {
    { 0, 0, 0, 3, false },
    { 1, 0, 1, 3, false },
  }, 2, false)
  input('cX<Esc>')
  wait_for(function()
    return vim.deep_equal(request('nvim_buf_get_lines', 0, 0, -1, true), { 'X', 'X' })
  end)
  input('u')
  wait_for(function()
    return vim.deep_equal(request('nvim_buf_get_lines', 0, 0, -1, true), { 'one', 'two' })
  end)
  assert(#request('nvim_helix_get_state', 0).selections == 2, 'undo lost selections')
  input('<F6>')
  wait_for(function()
    return vim.deep_equal(request('nvim_buf_get_lines', 0, 0, -1, true), { '/*one*/', '/*two*/' })
  end)
  input('mic')
  wait_for(function()
    for _, s in ipairs(request('nvim_helix_get_state', 0).selections) do
      local selected =
        table.concat(request('nvim_buf_get_text', 0, s[1], s[2], s[3], s[4], {}), '\n')
      if selected ~= 'one' and selected ~= 'two' then
        return false
      end
    end
    return true
  end)
end, debug.traceback)
pcall(request, 'nvim_command', 'qa!')
vim.fn.jobwait({ child }, 1000)
vim.fn.delete(temporary, 'rf')
assert(ok, err)
print('Installed native Helix mode and configuration: PASS')
