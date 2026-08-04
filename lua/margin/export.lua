local session = require('margin.session')
local config = require('margin.config')
local diffmap = require('margin.diffmap')

local M = {}

local PREAMBLE = 'I reviewed the changes. Please address the following comments.'

--- Ask whether to archive the comments an export just handed off.
---@param n integer
---@return boolean
local function confirm_archive(n)
  return vim.fn.confirm(('Archive %d exported comments?'):format(n), '&Yes\n&No', 1) == 1
end

--- Archive exported comments that are still active.
---@param sess margin.Session
---@param comments margin.Comment[]
---@return integer
local function archive_export(sess, comments)
  local selected = {}
  for _, comment in ipairs(comments) do
    selected[comment.id] = true
  end

  local active = {}
  for _, comment in ipairs(sess.comments) do
    if selected[comment.id] and not comment.archived then
      active[#active + 1] = comment
    end
  end
  if #active == 0 or not confirm_archive(#active) then
    return 0
  end

  local archived = session.archive_comments(sess, active)
  if archived > 0 then
    require('margin.render').schedule()
  end
  return archived
end

---@class margin.ExportFile
---@field buf? integer
---@field win? integer
---@field loaded? boolean
---@field lines? string[]
---@field language? string

---@class margin.ExportContext
---@field files table<string, margin.ExportFile>
---@field diffs table<string, table[]>

--- Create caches for one export.
---@return margin.ExportContext
local function export_context()
  local files = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local path = vim.api.nvim_buf_get_name(buf)
    if path ~= '' and not files[path] then
      files[path] = { buf = buf, win = win }
    end
  end
  return { files = files, diffs = {} }
end

--- Read and cache the data for a file.
---@param ctx margin.ExportContext
---@param abs string
---@return margin.ExportFile
local function file_data(ctx, abs)
  local data = ctx.files[abs] or {}
  ctx.files[abs] = data
  if data.loaded then
    return data
  end
  data.loaded = true

  if data.buf and vim.api.nvim_buf_is_loaded(data.buf) then
    data.lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  elseif vim.fn.filereadable(abs) == 1 then
    data.lines = vim.fn.readfile(abs)
  end
  if data.buf and vim.bo[data.buf].filetype ~= '' then
    data.language = vim.bo[data.buf].filetype
  else
    data.language = vim.filetype.match({ filename = abs }) or ''
  end
  return data
end

--- The unified-diff hunk containing `lnum` on the given side, or nil.
--- `side` selects which of the `@@ -old +new @@` ranges to match against.
---@param ctx margin.ExportContext
---@param buf_a integer counterpart buffer (old side, text_a)
---@param buf_b integer source buffer (new side, text_b)
---@param lnum integer 1-based line on the comment's side
---@param side "new"|"old"
---@return string|nil hunk text (header + body)
local function diff_hunk(ctx, buf_a, buf_b, lnum, side)
  local key = ('%d:%d'):format(buf_a, buf_b)
  local hunks = ctx.diffs[key]
  if not hunks then
    hunks = {}
    ctx.diffs[key] = hunks
    local unified = vim.text.diff(diffmap.buf_text(buf_a), diffmap.buf_text(buf_b), {
      ctxlen = config.current.context_lines,
    }) --[[@as string]]
    local cur
    for _, line in ipairs(vim.split(unified or '', '\n', { plain = true })) do
      if line:match('^@@ ') then
        cur = { header = line, body = {} }
        hunks[#hunks + 1] = cur
      elseif cur and line ~= '' then
        cur.body[#cur.body + 1] = line
      end
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
---@param ctx margin.ExportContext
---@param sess margin.Session
---@param comment margin.Comment
---@return string|nil fenced block
local function context_block(ctx, sess, comment)
  local abs = session.abspath(sess, comment)
  local visible = ctx.files[abs]
  local buf = visible and visible.buf
  local win = visible and visible.win

  if buf and win and vim.wo[win].diff then
    local cp_buf = diffmap.counterpart(win)
    if cp_buf then
      -- Unified diff wants text_a = old, text_b = new. A new-side comment
      -- sits in the new buffer (its counterpart is old); an old-side comment
      -- sits in the old buffer (its counterpart is new), so swap accordingly.
      local buf_a, buf_b
      if comment.side == 'old' then
        buf_a, buf_b = buf, cp_buf
      else
        buf_a, buf_b = cp_buf, buf
      end
      local hunk = diff_hunk(ctx, buf_a, buf_b, comment.lnum, comment.side)
      if hunk then
        return '```diff\n' .. hunk .. '\n```'
      end
    end
  end

  local data = file_data(ctx, abs)
  local lines = data.lines
  if not lines then
    return nil
  end
  local context_lines = config.current.context_lines
  local lo = math.max(1, comment.lnum - context_lines)
  local hi = math.min(#lines, comment.end_lnum + context_lines)
  if lo > #lines then
    return nil
  end
  local snippet = vim.list_slice(lines, lo, hi)
  local lang = data.language or ''
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
  if comment.archived then
    anchor = anchor .. ' (archived)'
  end
  return '## ' .. anchor
end

--- Render selected comments to the export format.
---@param sess margin.Session
---@param comments margin.Comment[]
---@return string
local function render_comments(sess, comments)
  table.sort(comments, function(a, b)
    if a.path == b.path then
      return a.lnum < b.lnum
    end
    return a.path < b.path
  end)

  local ctx = export_context()
  local parts = { PREAMBLE }
  for _, comment in ipairs(comments) do
    local body = comment.text
    if comment.orphaned then
      body = body .. '\n\n(position can be stale)'
    end
    local section = { header(comment), '', body }
    local block = context_block(ctx, sess, comment)
    if block then
      section[#section + 1] = ''
      section[#section + 1] = block
    end
    parts[#parts + 1] = table.concat(section, '\n')
  end

  return table.concat(parts, '\n\n') .. '\n'
end

--- Render the session to the export format.
---@param sess margin.Session
---@param include_archived boolean|nil
---@return string
function M.render(sess, include_archived)
  return render_comments(sess, session.select_comments(sess, include_archived))
end

local BUFNAME = 'margin://export'

---@class margin.ExportPreview
---@field win integer
---@field session margin.Session
---@field comments margin.Comment[]
---@field offer_archive boolean

---@type table<integer, margin.ExportPreview>
local previews = {}

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

--- Offer to archive the active comments represented by a closing preview.
---@param buf integer
local function close_preview(buf)
  local preview = previews[buf]
  previews[buf] = nil
  if not preview then
    return
  end

  -- BufWipeout can run while :quit is already closing this window. Defer the
  -- close so that path can finish first; buffer-switching close mappings leave
  -- the preview's split alive, and this removes it on the next event-loop turn.
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(preview.win) then
      pcall(vim.api.nvim_win_close, preview.win, true)
    end
  end)

  if not preview.offer_archive then
    return
  end

  archive_export(preview.session, preview.comments)
end

--- Show the markdown in the export scratch buffer, in a split below.
--- Re-exporting reuses the buffer (and its window when still visible).
---@param markdown string
---@param sess margin.Session
---@param exported margin.Comment[]
---@param offer_archive boolean
local function show(markdown, sess, exported, offer_archive)
  local buf = export_buf()
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, BUFNAME)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      callback = function(ev)
        close_preview(ev.buf)
      end,
    })
  end
  local text = markdown:gsub('\n$', '')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))

  local win = vim.fn.win_findbuf(buf)[1]
  if win then
    vim.api.nvim_set_current_win(win)
  else
    win = vim.api.nvim_open_win(buf, true, { split = 'below', win = -1 })
  end
  previews[buf] = { win = win, session = sess, comments = exported, offer_archive = offer_archive }
end

--- Export the current session. With `path`, writes a file and offers to archive
--- what it wrote; otherwise opens the markdown in a scratch split that offers
--- the same when it closes. Declining keeps the comments active for a re-export.
---
--- Archived comments are excluded unless `include_archived` is set, in which
--- case the re-dump archives nothing and never prompts.
---@param path string|nil
---@param include_archived boolean|nil
---@return string markdown
function M.run(path, include_archived)
  local sess = session.for_buf(vim.api.nvim_get_current_buf())

  local exported = session.select_comments(sess, include_archived)
  if #exported == 0 then
    vim.notify('margin: no comments to export', vim.log.levels.WARN)
    return ''
  end

  local markdown = render_comments(sess, exported)

  if not path or path == '' then
    show(markdown, sess, exported, not include_archived)
    return markdown
  end

  local files = {}
  for _, c in ipairs(exported) do
    files[c.path] = true
  end
  local abs = vim.fn.fnamemodify(path, ':p')
  vim.fn.writefile(vim.split(markdown, '\n', { plain = true }), abs)

  local archived = 0
  if not include_archived then
    archived = archive_export(sess, exported)
  end
  local suffix = archived > 0 and (', archived %d'):format(archived) or ''
  vim.notify(
    ('margin: exported %d comments (%d files) to %s%s'):format(
      #exported,
      vim.tbl_count(files),
      abs,
      suffix
    )
  )
  return markdown
end

return M
