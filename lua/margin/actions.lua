local session = require('margin.session')
local config = require('margin.config')

local M = {}

--- The innermost visible comment whose live range contains the cursor line.
--- Smallest range wins when several overlap. Hidden (archived, not shown)
--- comments are skipped; show them with `:Margin archived` to act on them.
---@param buf integer
---@param lnum integer 1-based cursor line
---@return margin.Comment|nil
---@return margin.Session|nil
local function comment_at(buf, lnum)
  local path = session.path_for_buf(buf)
  if not path then
    return nil
  end
  local sess = session.for_buf(buf)
  local anchor = require('margin.anchor')
  local best, best_span
  for _, c in ipairs(session.comments_for_path(sess, path)) do
    if config.visible(c) then
      local s, e = anchor.range(buf, c)
      if lnum >= s and lnum <= e then
        local span = e - s
        if not best or span < best_span then
          best, best_span = c, span
        end
      end
    end
  end
  return best, sess
end

--- Comment on the current line or a visual/command range.
---@param opts { line1?: integer, line2?: integer }|nil
function M.comment(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local lnum = opts.line1 or vim.api.nvim_win_get_cursor(win)[1]
  local end_lnum = opts.line2 or lnum
  if end_lnum < lnum then
    lnum, end_lnum = end_lnum, lnum
  end

  -- Validate we can resolve a path before opening the composer.
  local path, _, err = session.resolve_path(buf, win)
  if not path then
    vim.notify(err or 'margin: cannot resolve path', vim.log.levels.ERROR)
    return
  end

  local title = ('%s:%d'):format(path, lnum)
  if end_lnum > lnum then
    title = title .. ('-%d'):format(end_lnum)
  end

  require('margin.editor').open({
    title = title,
    on_submit = function(text)
      local c, add_err = session.add(buf, lnum, end_lnum, text, win)
      if not c then
        if add_err then
          vim.notify(add_err, vim.log.levels.ERROR)
        end
        return
      end
      require('margin.anchor').ensure(buf)
      require('margin.render').redraw()
    end,
  })
end

--- Edit the comment under the cursor.
function M.edit()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local comment, sess = comment_at(buf, lnum)
  if not comment or not sess then
    vim.notify('margin: no comment under cursor', vim.log.levels.WARN)
    return
  end
  require('margin.editor').open({
    title = ('%s:%d'):format(comment.path, comment.lnum),
    text = comment.text,
    on_submit = function(text)
      session.edit(sess, comment, text)
      require('margin.render').redraw()
    end,
  })
end

--- Delete the comment under the cursor.
function M.delete()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local comment, sess = comment_at(buf, lnum)
  if not comment or not sess then
    vim.notify('margin: no comment under cursor', vim.log.levels.WARN)
    return
  end
  session.delete(sess, comment)
  require('margin.render').redraw()
end

--- Set the archived flag on the comment under the cursor, then redraw.
---@param archived boolean
local function set_archived_at_cursor(archived)
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local comment, sess = comment_at(buf, lnum)
  if not comment or not sess then
    vim.notify('margin: no comment under cursor', vim.log.levels.WARN)
    return
  end
  session.set_archived(sess, comment, archived)
  require('margin.render').redraw()
end

--- Archive the comment under the cursor (excludes it from export/list).
function M.archive()
  set_archived_at_cursor(true)
end

--- Unarchive the comment under the cursor.
function M.unarchive()
  set_archived_at_cursor(false)
end

--- Toggle inline boxes (signs stay).
function M.toggle_inline()
  config.current.inline = not config.current.inline
  require('margin.render').redraw()
end

--- Toggle visibility of archived comments (shown dimmed with an (archived)
--- tag). They stay out of export and the comment list regardless.
function M.toggle_archived()
  config.current.show_archived = not config.current.show_archived
  local state = config.current.show_archived and 'shown' or 'hidden'
  vim.notify('margin: archived comments ' .. state, vim.log.levels.INFO)
  require('margin.render').redraw()
end

--- Export the session. File exports prompt before archiving; scratch previews
--- prompt when closed. Declining (Esc / No) keeps comments active for a
--- re-export. `include_archived` re-dumps never archive or prompt.
---@param path string|nil
---@param include_archived boolean|nil
---@return string markdown
function M.export(path, include_archived)
  local archive = false
  if path and path ~= '' and not include_archived then
    local sess = session.for_buf(vim.api.nvim_get_current_buf())
    local n = #session.select_comments(sess, false)
    if n > 0 then
      local choice = vim.fn.confirm(('Archive %d exported comments?'):format(n), '&Yes\n&No', 1)
      archive = choice == 1
    end
  end
  return require('margin.export').run(path, include_archived, archive)
end

--- Delete every comment in the current session after confirmation.
function M.clear()
  local buf = vim.api.nvim_get_current_buf()
  local sess = session.for_buf(buf)
  if #sess.comments == 0 then
    vim.notify('margin: no comments to clear', vim.log.levels.INFO)
    return
  end
  local choice = vim.fn.confirm(
    ('Delete all %d comments in this session?'):format(#sess.comments),
    '&Yes\n&No',
    2
  )
  if choice ~= 1 then
    return
  end
  session.clear(sess)
  require('margin.render').redraw()
end

--- Expose the cursor-hit lookup for the quickfix motions.
M.comment_at = comment_at

return M
