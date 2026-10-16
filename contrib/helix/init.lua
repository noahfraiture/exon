-- Minimal configuration for the native fork. No plugin installation or
-- filesystem changes are performed when loading this file.
vim.o.helix = true

vim.o.number = true
vim.o.termguicolors = true
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.autoindent = true
vim.o.completeopt = 'menu,menuone,noselect'
vim.o.statusline = '%f %m%=%{v:lua.vim.helix.statusline()} %l:%c '

local map = function(lhs, rhs, description)
  vim.keymap.set('h', lhs, rhs, { silent = true, desc = description })
end

map('<Space>w', '<Cmd>write<CR>', 'Save')
map('<Space>q', '<Cmd>confirm quit<CR>', 'Quit')
map('<Space>e', '<Cmd>edit .<CR>', 'Files')
map('<Space>:', ':', 'Command')
map('<Space>n', '<Cmd>bnext<CR>', 'Next buffer')
map('<Space>p', '<Cmd>bprevious<CR>', 'Previous buffer')
map('<Space>b', function()
  local buffers = vim.tbl_filter(function(buf)
    return vim.bo[buf].buflisted
  end, vim.api.nvim_list_bufs())
  vim.ui.select(buffers, {
    prompt = 'Buffers',
    format_item = function(buf)
      local file = vim.api.nvim_buf_get_name(buf)
      return file == '' and '[No Name]' or vim.fn.fnamemodify(file, ':~:.')
    end,
  }, function(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_set_current_buf(buf)
    end
  end)
end, 'Buffers')

map('gd', vim.lsp.buf.definition, 'Definition')
map('gr', vim.lsp.buf.references, 'References')
map('<Space>k', vim.lsp.buf.hover, 'Documentation')
map('<Space>r', vim.lsp.buf.rename, 'Rename symbol')
map('<Space>a', vim.lsp.buf.code_action, 'Code actions at primary cursor')
map('<Space>f', vim.helix.format, 'Format selections')
map(']d', function()
  vim.diagnostic.jump({ count = 1, float = true })
end, 'Next diagnostic')
map('[d', function()
  vim.diagnostic.jump({ count = -1, float = true })
end, 'Previous diagnostic')

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('helix.example.lsp', { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})

-- The default textobjects need no mappings: mim, mi(, ma/, miw, etc.
-- Custom commands can use native selection APIs. For example:
-- map('Q', function() vim.helix.textobject('m') end, 'Inside closest surround')
--
-- Optional plugins can still be installed with vim.pack.add(...). Their file
-- pickers/special buffers use ordinary Vim mode; bind actions with map(...).
