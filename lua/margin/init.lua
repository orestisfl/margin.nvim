local M = {}

--- Configure margin. Optional: every command works with defaults.
---@param opts margin.Config|nil
function M.setup(opts)
  if vim.fn.has('nvim-0.12') == 0 then
    vim.notify('margin.nvim requires Neovim 0.12+', vim.log.levels.ERROR)
    return
  end
  require('margin.config').setup(opts)
  require('margin.autocmds').setup()
end

--- Comment on a line or range in the current buffer.
--- Opens the floating composer; the comment is created on save.
---@param opts { line1?: integer, line2?: integer }|nil
function M.comment(opts)
  require('margin.actions').comment(opts)
end

--- Edit the innermost comment under the cursor.
function M.edit()
  require('margin.actions').edit()
end

--- Delete the innermost comment under the cursor.
function M.delete()
  require('margin.actions').delete()
end

--- Populate and open the quickfix list with all session comments.
function M.list()
  require('margin.qf').list()
end

--- Jump to the next comment in the current buffer (wraps).
function M.next()
  require('margin.qf').next()
end

--- Jump to the previous comment in the current buffer (wraps).
function M.prev()
  require('margin.qf').prev()
end

--- Toggle inline comment boxes at runtime (signs remain).
function M.toggle_inline()
  require('margin.actions').toggle_inline()
end

--- Delete all comments in the current session (after confirmation).
function M.clear()
  require('margin.actions').clear()
end

--- Export the current session as markdown.
--- With a path, writes to that file; otherwise copies to the clipboard.
---@param path string|nil
---@return string markdown
function M.export(path)
  return require('margin.export').run(path)
end

return M
