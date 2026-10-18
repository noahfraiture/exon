-- Explicit adapters for plugins that do not know Exon's h/hv mapping modes.
-- Do not disguise the editor's real mode or copy arbitrary normal-mode maps.
local M = {}
local which_key_patched = false

--- Prepare which-key options for native Helix mode. Call before its setup().
--- The plugin is loaded only when this adapter is explicitly requested.
--- @param opts? table Ordinary which-key setup options.
--- @return table opts A copy with h-mode triggers included.
function M.which_key(opts)
  local util = require('which-key.util')
  local state = require('which-key.state')
  if not which_key_patched then
    if util.mapmode('h') ~= 'h' then
      local mapmode = util.mapmode
      util.mapmode = function(mode)
        mode = mode or vim.api.nvim_get_mode().mode
        return mode:sub(1, 1) == 'h' and 'h' or mapmode(mode)
      end
    end
    -- h/hv share mappings. Queued input on this internal transition should
    -- not suspend triggers (for example, quickly typing v Space c f).
    local safe = state.safe
    state.safe = function(change)
      if (change == 'h:hv' or change == 'hv:h') and not util.in_macro() then
        return true
      end
      return safe(change)
    end
    which_key_patched = true
  end
  opts = vim.deepcopy(opts or {})
  opts.triggers = opts.triggers or { { '<auto>', mode = 'nxso' } }
  for _, trigger in ipairs(opts.triggers) do
    if trigger.mode and trigger.mode:find('n', 1, true) and not trigger.mode:find('h', 1, true) then
      trigger.mode = trigger.mode .. 'h'
    end
  end
  return opts
end

return M
