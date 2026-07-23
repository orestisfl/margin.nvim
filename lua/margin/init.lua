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

--- Populate and open the quickfix list with session comments.
--- Archived comments are omitted unless `include_archived` is set.
---@param include_archived boolean|nil
function M.list(include_archived)
  require('margin.qf').list(include_archived)
end

--- Archive the comment under the cursor (excludes it from export and list).
function M.archive()
  require('margin.actions').archive()
end

--- Unarchive the comment under the cursor.
function M.unarchive()
  require('margin.actions').unarchive()
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

--- Toggle visibility of archived comments (rendered dimmed when shown).
function M.toggle_archived()
  require('margin.actions').toggle_archived()
end

--- Delete all comments in the current session (after confirmation).
function M.clear()
  require('margin.actions').clear()
end

--- Export the current session as markdown.
--- With a path, writes to that file and archives the comments written (no
--- prompt; the interactive `:Margin export` asks first). Otherwise opens a
--- scratch split. Archived comments are excluded, and archiving is skipped,
--- unless `include_archived` is set.
---@param path string|nil
---@param include_archived boolean|nil
---@return string markdown
function M.export(path, include_archived)
  local archive = path ~= nil and path ~= '' and not include_archived
  return require('margin.export').run(path, include_archived, archive)
end

return M
