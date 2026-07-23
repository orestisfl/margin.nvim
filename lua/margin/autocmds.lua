local session = require('margin.session')

local M = {}

local group = 'margin'
local installed = false

--- Install margin's autocmds. Idempotent; safe to call without setup().
function M.setup()
  if installed then
    return
  end
  installed = true

  local augroup = vim.api.nvim_create_augroup(group, { clear = true })

  -- Final flush so live positions survive a clean exit.
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      session.persist_all()
    end,
  })

  -- Re-anchor and render buffers that carry comments as they load / show.
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWinEnter' }, {
    group = augroup,
    callback = function(ev)
      require('margin.anchor').on_buf_load(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'DiffUpdated' }, {
    group = augroup,
    callback = function()
      require('margin.render').schedule()
    end,
  })

  -- Catch up on buffers already open when margin loads. Under lazy-loading the
  -- plugin activates after those buffers' BufReadPost has fired, so re-anchor
  -- and render them here; new buffers are handled by the autocmds above.
  vim.schedule(function()
    require('margin.anchor').reanchor_all()
  end)
end

return M
