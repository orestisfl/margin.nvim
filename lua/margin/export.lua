local session = require('margin.session')
local config = require('margin.config')
local diffmap = require('margin.diffmap')

local M = {}

local PREAMBLE = 'I reviewed the changes. Please address the following comments.'

--- Absolute path for a comment's stored path.
---@param sess margin.Session
---@param comment margin.Comment
---@return string
local function abspath(sess, comment)
  if comment.path:sub(1, 1) == '/' then
    return comment.path
  end
  return sess.root .. '/' .. comment.path
end

--- A loaded buffer currently displayed in a window for `path`, plus its win.
--- Returns nil when the file is not visible.
---@param abs string absolute path
---@return integer|nil buf
---@return integer|nil win
local function visible_buf(abs)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(buf) == abs then
      return buf, win
    end
  end
  return nil
end

--- Filetype for a fenced code block, from a loaded buffer or the extension.
---@param abs string
---@param buf integer|nil
---@return string
local function language(abs, buf)
  if buf and vim.bo[buf].filetype ~= '' then
    return vim.bo[buf].filetype
  end
  return vim.filetype.match({ filename = abs }) or ''
end

--- Lines of a file, from the loaded buffer if any, else read from disk.
---@param abs string
---@param buf integer|nil
---@return string[]|nil
local function file_lines(abs, buf)
  if buf and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  if vim.fn.filereadable(abs) == 1 then
    return vim.fn.readfile(abs)
  end
  return nil
end

--- The unified-diff hunk containing `lnum` on the given side, or nil.
--- `side` selects which of the `@@ -old +new @@` ranges to match against.
---@param buf_a integer counterpart buffer (old side, text_a)
---@param buf_b integer source buffer (new side, text_b)
---@param lnum integer 1-based line on the comment's side
---@param side "new"|"old"
---@return string|nil hunk text (header + body)
local function diff_hunk(buf_a, buf_b, lnum, side)
  local ta = table.concat(vim.api.nvim_buf_get_lines(buf_a, 0, -1, false), '\n') .. '\n'
  local tb = table.concat(vim.api.nvim_buf_get_lines(buf_b, 0, -1, false), '\n') .. '\n'
  local unified = vim.text.diff(ta, tb, { ctxlen = config.current.context_lines }) --[[@as string]]
  if not unified or unified == '' then
    return nil
  end

  local lines = vim.split(unified, '\n', { plain = true })
  local hunks = {}
  local cur
  for _, line in ipairs(lines) do
    if line:match('^@@ ') then
      cur = { header = line, body = {} }
      hunks[#hunks + 1] = cur
    elseif cur and line ~= '' then
      cur.body[#cur.body + 1] = line
    end
  end

  for _, h in ipairs(hunks) do
    local oa, oc, nb, nc = h.header:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
    if oa then
      local start, count
      if side == 'old' then
        start, count = tonumber(oa), tonumber(oc ~= '' and oc or '1')
      else
        start, count = tonumber(nb), tonumber(nc ~= '' and nc or '1')
      end
      if start and count and lnum >= start and lnum <= start + math.max(count, 1) - 1 then
        return h.header .. '\n' .. table.concat(h.body, '\n')
      end
    end
  end
  return nil
end

--- The context block for a comment: a diff hunk when live in a diff window,
--- otherwise a code snippet, otherwise nothing.
---@param sess margin.Session
---@param comment margin.Comment
---@return string|nil fenced block
local function context_block(sess, comment)
  local abs = abspath(sess, comment)
  local buf, win = visible_buf(abs)

  if buf and win and vim.wo[win].diff then
    local cp = diffmap.counterpart(win)
    if cp then
      -- Unified diff wants text_a = old, text_b = new. A new-side comment
      -- sits in the new buffer (its counterpart is old); an old-side comment
      -- sits in the old buffer (its counterpart is new), so swap accordingly.
      local buf_a, buf_b
      if comment.side == 'old' then
        buf_a, buf_b = buf, cp.buf
      else
        buf_a, buf_b = cp.buf, buf
      end
      local hunk = diff_hunk(buf_a, buf_b, comment.lnum, comment.side)
      if hunk then
        return '```diff\n' .. hunk .. '\n```'
      end
    end
  end

  local lines = file_lines(abs, buf)
  if not lines then
    return nil
  end
  local ctx = config.current.context_lines
  local lo = math.max(1, comment.lnum - ctx)
  local hi = math.min(#lines, comment.end_lnum + ctx)
  if lo > #lines then
    return nil
  end
  local snippet = vim.list_slice(lines, lo, hi)
  local lang = language(abs, buf)
  return '```' .. lang .. '\n' .. table.concat(snippet, '\n') .. '\n```'
end

--- Header anchor line for a comment.
---@param comment margin.Comment
---@return string
local function header(comment)
  local anchor = comment.path .. ':' .. comment.lnum
  if comment.end_lnum > comment.lnum then
    anchor = anchor .. '-' .. comment.end_lnum
  end
  if comment.side == 'old' then
    anchor = anchor .. ' (old version)'
  end
  return '## ' .. anchor
end

--- Render the whole session to the fixed markdown export format.
---@param sess margin.Session
---@return string
function M.render(sess)
  local comments = vim.deepcopy(sess.comments)
  table.sort(comments, function(a, b)
    if a.path == b.path then
      return a.lnum < b.lnum
    end
    return a.path < b.path
  end)

  local parts = { PREAMBLE }
  for _, comment in ipairs(comments) do
    local body = comment.text
    if comment.orphaned then
      body = body .. '\n\n(position may be stale)'
    end
    local section = { header(comment), '', body }
    local block = context_block(sess, comment)
    if block then
      section[#section + 1] = ''
      section[#section + 1] = block
    end
    parts[#parts + 1] = table.concat(section, '\n')
  end

  return table.concat(parts, '\n\n') .. '\n'
end

local BUFNAME = 'margin://export'

--- The existing export scratch buffer, if any.
---@return integer|nil
local function export_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == BUFNAME then
      return buf
    end
  end
  return nil
end

--- Show the markdown in the export scratch buffer, in a split below.
--- Re-exporting reuses the buffer (and its window when still visible).
---@param markdown string
local function show(markdown)
  local buf = export_buf()
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, BUFNAME)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
  end
  local text = markdown:gsub('\n$', '')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))

  local win = vim.fn.win_findbuf(buf)[1]
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_open_win(buf, true, { split = 'below', win = -1 })
  end
end

--- Export the current session. With `path`, writes a file; otherwise opens
--- the markdown in a scratch split. Returns the rendered markdown.
---@param path string|nil
---@return string markdown
function M.run(path)
  local sess = session.for_buf(vim.api.nvim_get_current_buf())
  if #sess.comments == 0 then
    vim.notify('margin: no comments to export', vim.log.levels.WARN)
    return ''
  end

  local markdown = M.render(sess)

  if path and path ~= '' then
    local files = {}
    for _, c in ipairs(sess.comments) do
      files[c.path] = true
    end
    local abs = vim.fn.fnamemodify(path, ':p')
    vim.fn.writefile(vim.split(markdown, '\n', { plain = true }), abs)
    vim.notify(
      ('margin: exported %d comments (%d files) to %s'):format(
        #sess.comments,
        vim.tbl_count(files),
        abs
      )
    )
  else
    show(markdown)
  end

  return markdown
end

return M
