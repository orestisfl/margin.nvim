local session = require('margin.session')
local config = require('margin.config')

local M = {}

--- The innermost comment whose live range contains the cursor line.
--- Smallest range wins when several overlap.
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
    local s, e = anchor.range(buf, c)
    if lnum >= s and lnum <= e then
      local span = e - s
      if not best or span < best_span then
        best, best_span = c, span
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

--- Toggle inline boxes (signs stay).
function M.toggle_inline()
  config.current.inline = not config.current.inline
  require('margin.render').redraw()
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
