local session = require('margin.session')
local config = require('margin.config')

local M = {}

--- First line of a comment body (quickfix shows one line per comment).
---@param comment margin.Comment
---@return string
local function first_line(comment)
  local line = vim.split(comment.text, '\n', { plain = true })[1] or ''
  if comment.archived then
    return '[archived] ' .. line
  end
  if comment.orphaned then
    return '[stale] ' .. line
  end
  return line
end

--- Populate and open the quickfix list with the session's comments.
---@param include_archived boolean|nil
function M.list(include_archived)
  local sess = session.for_buf(vim.api.nvim_get_current_buf())

  local items = {}
  for _, c in ipairs(session.select_comments(sess, include_archived)) do
    items[#items + 1] = {
      filename = session.abspath(sess, c),
      lnum = c.lnum,
      text = first_line(c),
    }
  end
  if #items == 0 then
    vim.notify('margin: no comments', vim.log.levels.INFO)
    return
  end
  table.sort(items, function(a, b)
    if a.filename == b.filename then
      return a.lnum < b.lnum
    end
    return a.filename < b.filename
  end)

  vim.fn.setqflist({}, ' ', { title = 'margin comments', items = items })
  vim.cmd('copen')
end

--- Visible comments in the current buffer sorted by their live line position.
--- Hidden (archived, not shown) comments are skipped so motions never land on
--- an invisible box.
---@return margin.Comment[]
---@return table<string, integer> id -> live lnum
local function current_buffer_comments()
  local buf = vim.api.nvim_get_current_buf()
  local path = session.path_for_buf(buf)
  if not path then
    return {}, {}
  end
  local sess = session.for_buf(buf)
  local anchor = require('margin.anchor')
  local comments = {}
  for _, c in ipairs(session.comments_for_path(sess, path)) do
    if config.visible(c) then
      comments[#comments + 1] = c
    end
  end
  local live = {}
  for _, c in ipairs(comments) do
    live[c.id] = (anchor.range(buf, c))
  end
  table.sort(comments, function(a, b)
    return live[a.id] < live[b.id]
  end)
  return comments, live
end

--- Jump toward the next/previous comment in the current buffer (wraps).
---@param dir 1|-1
local function jump(dir)
  local comments, live = current_buffer_comments()
  if #comments == 0 then
    vim.notify('margin: no comments in buffer', vim.log.levels.INFO)
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)[1]

  local target
  if dir == 1 then
    for _, c in ipairs(comments) do
      if live[c.id] > cur then
        target = c
        break
      end
    end
    target = target or comments[1] -- wrap to first
  else
    for i = #comments, 1, -1 do
      if live[comments[i].id] < cur then
        target = comments[i]
        break
      end
    end
    target = target or comments[#comments] -- wrap to last
  end

  vim.api.nvim_win_set_cursor(0, { live[target.id], 0 })
end

function M.next()
  jump(1)
end

function M.prev()
  jump(-1)
end

return M
