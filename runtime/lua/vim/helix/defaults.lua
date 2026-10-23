-- Shared editor actions use Neovim APIs. Selection editing stays in commands.lua.
-- This table is also the source of the actual, discoverable h-mode mappings.
local M = {}

local function native(keys, count)
  vim.cmd.normal({
    args = { tostring(count) .. vim.api.nvim_replace_termcodes(keys, true, false, true) },
    bang = true,
  })
end

local function lsp(method)
  return function()
    vim.lsp.buf[method]()
  end
end

--- @param direction integer
--- @param boundary? boolean
local function diagnostic(direction, boundary)
  --- @param count integer
  return function(count)
    local opts = {
      count = direction * (boundary and vim._maxint or count),
    }
    if boundary then
      opts.wrap = false
    end
    vim.diagnostic.jump(opts)
  end
end

--- @type table<string, [fun(count: integer), string]>
M.bindings = {
  ['[d'] = { diagnostic(-1), 'Previous diagnostic' },
  [']d'] = { diagnostic(1), 'Next diagnostic' },
  ['[D'] = { diagnostic(-1, true), 'First diagnostic' },
  [']D'] = { diagnostic(1, true), 'Last diagnostic' },
  gd = { lsp('definition'), 'Definition' },
  gD = { lsp('declaration'), 'Declaration' },
  gy = { lsp('type_definition'), 'Type definition' },
  gr = { lsp('references'), 'References' },
  gi = { lsp('implementation'), 'Implementation' },
  gn = {
    function(count)
      vim.cmd.bnext({ count = count })
    end,
    'Next buffer',
  },
  gp = {
    function(count)
      vim.cmd.bprevious({ count = count })
    end,
    'Previous buffer',
  },
  ga = {
    function()
      vim.cmd.buffer('#')
    end,
    'Alternate file',
  },
  gf = {
    function(count)
      native('gf', count)
    end,
    'Open file under cursor',
  },
  ['<C-o>'] = {
    function(count)
      native('<C-o>', count)
    end,
    'Previous jump',
  },
  ['<C-i>'] = {
    function(count)
      native('<C-i>', count)
    end,
    'Next jump',
  },
  ['<Space>k'] = { lsp('hover'), 'Documentation' },
  ['<Space>r'] = { lsp('rename'), 'Rename symbol' },
  ['<Space>a'] = { lsp('code_action'), 'Code action at primary cursor' },
  ['='] = {
    function()
      vim.helix.format()
    end,
    'Format selections',
  },
}

function M.install()
  for lhs, binding in pairs(M.bindings) do
    -- Install before user configuration, and never overwrite an existing map
    -- if this module is explicitly reloaded by a user.
    if vim.fn.maparg(lhs, 'h') == '' then
      vim.keymap.set('h', lhs, function()
        vim.helix._run_builtin(lhs)
      end, { silent = true, desc = binding[2] })
    end
  end
end

return M
