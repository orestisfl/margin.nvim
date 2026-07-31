local session = require('margin.session')
local config = require('margin.config')

local M = {}

--- Namespace for anchor extmarks (position source of truth + signs).
M.ns = vim.api.nvim_create_namespace('margin.anchor')

--- Radius (in lines) scanned around the stored position when re-anchoring.
local SCAN_RADIUS = 40

--- Live extmark ids per buffer, keyed by comment id.
---@type table<integer, table<string, integer>>
local marks = {}

--- Trimmed comparison so leading/trailing whitespace churn doesn't break match.
local trim = vim.trim

--- Sign-column highlight for a comment by state, or nil when it has no sign.
--- Hidden (archived, not shown) comments keep a position mark but no sign;
--- archived-and-shown dims over stale.
---@param comment margin.Comment
---@return string|nil
local function sign_hl(comment)
  if not config.visible(comment) then
    return nil
  end
  if comment.archived then
    return 'MarginArchived'
  end
  if comment.orphaned then
    return 'MarginOrphan'
  end
  return 'MarginSign'
end

--- Place or update a comment's extmark at `row`..`end_row` (0-based).
---@param buf integer
---@param comment margin.Comment
---@param row integer
---@param end_row integer
local function place_mark(buf, comment, row, end_row)
  local end_line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ''
  local hl = sign_hl(comment)
  marks[buf] = marks[buf] or {}
  marks[buf][comment.id] = vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
    id = marks[buf][comment.id],
    end_row = end_row,
    end_col = #end_line,
    right_gravity = false,
    end_right_gravity = true,
    invalidate = true,
    sign_text = hl and config.current.sign_text,
    sign_hl_group = hl,
  })
end

--- Place (or replace) the anchor extmark for a comment at its stored position.
---@param buf integer
---@param comment margin.Comment
local function set_mark(buf, comment)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local row = math.max(0, math.min(comment.lnum - 1, line_count - 1))
  local end_row = math.max(row, math.min(comment.end_lnum - 1, line_count - 1))
  place_mark(buf, comment, row, end_row)
end

--- Find a unique trimmed match for `needle` within ±radius of `around`.
--- Returns the 1-based line, or nil when there are zero or multiple matches.
---@param buf integer
---@param needle string
---@param around integer 1-based
---@param radius integer
---@return integer|nil
local function unique_match(buf, needle, around, radius)
  local target = trim(needle)
  if target == '' then
    return nil
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local lo = math.max(1, around - radius)
  local hi = math.min(count, around + radius)
  local lines = vim.api.nvim_buf_get_lines(buf, lo - 1, hi, false)

  local found, ambiguous
  for i, l in ipairs(lines) do
    if trim(l) == target then
      if found then
        ambiguous = true
      else
        found = lo + i - 1
      end
    end
  end
  if ambiguous then
    return nil
  end
  return found
end

--- Re-anchor a single comment against the current buffer contents.
--- Exact match at stored line wins; else a unique nearby match relocates it;
--- else the comment is flagged orphaned. Un-orphans when a match reappears.
---@param buf integer
---@param comment margin.Comment
---@return boolean changed
local function reanchor_one(buf, comment)
  local count = vim.api.nvim_buf_line_count(buf)
  local at = math.max(1, math.min(comment.lnum, count))
  local cur = vim.api.nvim_buf_get_lines(buf, at - 1, at, false)[1] or ''

  local changed = false

  if trim(cur) == trim(comment.line_text) then
    if comment.orphaned then
      comment.orphaned = false
      changed = true
    end
    if comment.lnum ~= at then
      local span = comment.end_lnum - comment.lnum
      comment.lnum = at
      comment.end_lnum = at + span
      changed = true
    end
  else
    local hit = unique_match(buf, comment.line_text, comment.lnum, SCAN_RADIUS)
    if hit then
      local span = comment.end_lnum - comment.lnum
      comment.lnum = hit
      comment.end_lnum = math.min(hit + span, count)
      comment.line_text = vim.api.nvim_buf_get_lines(buf, hit - 1, hit, false)[1]
        or comment.line_text
      if comment.orphaned then
        comment.orphaned = false
      end
      changed = true
    elseif not comment.orphaned then
      comment.orphaned = true
      changed = true
    end
  end

  set_mark(buf, comment)
  return changed
end

--- Sync live extmark positions back into comments for one buffer.
--- Marks reported invalid flag their comment orphaned.
---@param buf integer
---@param comments margin.Comment[]
local function sync_from_marks(buf, comments)
  local bufmarks = marks[buf]
  if not bufmarks then
    return
  end
  for _, comment in ipairs(comments) do
    local id = bufmarks[comment.id]
    if id then
      local m = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, id, { details = true })
      if m and m[1] then
        local details = m[3] or {}
        if details.invalid then
          comment.orphaned = true
        elseif not comment.orphaned then
          -- Orphans keep their original line_text as the re-match search key.
          comment.lnum = m[1] + 1
          local end_row = details.end_row or m[1]
          comment.end_lnum = math.max(comment.lnum, end_row + 1)
          comment.line_text = vim.api.nvim_buf_get_lines(buf, m[1], m[1] + 1, false)[1]
            or comment.line_text
        end
      end
    end
  end
end

--- Re-anchor every comment for a buffer's stored path. Called on buffer load.
---@param buf integer
function M.on_buf_load(buf)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  local path = session.path_for_buf(buf)
  if not path then
    return
  end
  local sess = session.for_buf(buf)
  local comments = session.comments_for_path(sess, path)
  if #comments == 0 then
    return
  end

  local changed = false
  for _, comment in ipairs(comments) do
    if reanchor_one(buf, comment) then
      changed = true
    end
  end
  if changed then
    session.persist(sess)
  end
  require('margin.render').schedule()
end

--- Restore comments in all loaded buffers.
function M.reanchor_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.on_buf_load(buf)
    end
  end
end

--- Ensure anchor marks exist for all comments in a buffer, without re-scanning.
--- A mark whose sign no longer matches its comment's state is re-placed at its
--- live position, so recoloring never disturbs the tracked range.
---@param buf integer
---@param comments? margin.Comment[]
function M.ensure(buf, comments)
  if not comments then
    local path = session.path_for_buf(buf)
    if not path then
      return
    end
    comments = session.comments_for_path(session.for_buf(buf), path)
  end
  for _, comment in ipairs(comments) do
    local id = marks[buf] and marks[buf][comment.id]
    if not id then
      set_mark(buf, comment)
    else
      local m = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, id, { details = true })
      local d = m[3]
      if m[1] and d and not d.invalid and d.sign_hl_group ~= sign_hl(comment) then
        place_mark(buf, comment, m[1], d.end_row or m[1])
      end
    end
  end
end

--- Current 1-based [lnum, end_lnum] of a comment's live mark, or stored value.
---@param buf integer
---@param comment margin.Comment
---@return integer lnum
---@return integer end_lnum
function M.range(buf, comment)
  local id = marks[buf] and marks[buf][comment.id]
  if id then
    local m = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, id, { details = true })
    if m and m[1] and not (m[3] and m[3].invalid) then
      local end_row = (m[3] and m[3].end_row) or m[1]
      return m[1] + 1, end_row + 1
    end
  end
  return comment.lnum, comment.end_lnum
end

--- Delete all anchor marks. `ensure` restores marks for existing comments.
function M.clear_all()
  for buf in pairs(marks) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
  end
  marks = {}
end

--- Flush live extmark positions into a session's comments before it is saved.
---@param sess margin.Session
function M.sync_session(sess)
  local by_path = {}
  for _, c in ipairs(sess.comments) do
    by_path[c.path] = by_path[c.path] or {}
    table.insert(by_path[c.path], c)
  end
  for buf in pairs(marks) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local p = session.path_for_buf(buf)
      if p and by_path[p] then
        sync_from_marks(buf, by_path[p])
      end
    end
  end
end

--- Test isolation.
function M._reset()
  marks = {}
end

return M
