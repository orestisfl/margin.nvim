local config = require('margin.config')

local M = {}

--- `:checkhealth margin` report.
function M.check()
  vim.health.start('margin')

  if vim.fn.has('nvim-0.12') == 1 then
    vim.health.ok('Neovim 0.12+')
  else
    vim.health.error('margin.nvim requires Neovim 0.12+')
  end

  if vim.fn.has('clipboard') == 1 then
    vim.health.ok('clipboard provider available')
  else
    vim.health.warn('no clipboard provider; export still works via file or register')
  end

  local dir = config.data_dir()
  local count = 0
  if vim.fn.isdirectory(dir) == 1 then
    count = #vim.fn.glob(dir .. '/*.json', false, true)
  end
  vim.health.info(('data dir: %s'):format(dir))
  vim.health.info(('stored sessions: %d'):format(count))
end

return M
