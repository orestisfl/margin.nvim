local session = require('margin.session')
local config = require('margin.config')
local anchor = require('margin.anchor')
local diffmap = require('margin.diffmap')
local highlights = require('margin.highlights')

local M = {}

--- Comment-box virtual lines (attached to the source buffer).
M.ns_box = vim.api.nvim_create_namespace('margin.box')
--- Mirrored blank filler in the counterpart buffer, owned by source comments.
M.ns_filler = vim.api.nvim_create_namespace('margin.filler')

--- Wrap `text` (which may contain explicit newlines) to `width` columns.
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
  width = math.max(width, 8)
  local out = {}
  for _, paragraph in ipairs(vim.split(text, '\n', { plain = true })) do
    if paragraph == '' then
      out[#out + 1] = ''
    else
      local line = ''
      for word in paragraph:gmatch('%S+') do
        if line == '' then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. ' ' .. word
        else
          out[#out + 1] = line
          line = word
        end
      end
      if line ~= '' then
        out[#out + 1] = line
      end
    end
  end
  if #out == 0 then
    out[1] = ''
  end
  return out
end

--- A single dimmed summary line: the comment's first line plus a state tag.
---@param comment margin.Comment
---@param tag string parenthesized suffix without the parentheses
---@param hl string highlight group
---@return table[] virt_lines
local function summary_line(comment, tag, hl)
  local first = vim.split(comment.text, '\n', { plain = true })[1] or ''
  return { { { '└─ ' .. first .. ' (' .. tag .. ')', hl } } }
end

--- Virtual lines for a comment box: framed multi-line, or a one-line summary.
--- Orphaned comments collapse to a single stale line. Archived comments show
--- the full frame dimmed with an (archived) tag (only reached when visible).
---@param comment margin.Comment
---@param width integer
---@return table[] virt_lines (list of chunk-lists)
local function box_virt_lines(comment, width)
  if comment.orphaned then
    return summary_line(comment, 'stale', 'MarginOrphan')
  end

  local B, C = 'MarginBorder', 'MarginComment'
  if comment.archived then
    B, C = 'MarginArchived', 'MarginArchived'
  end

  local lines = wrap(comment.text, width - 3)
  if comment.archived then
    lines[#lines] = lines[#lines] .. ' (archived)'
  end
  if #lines == 1 then
    return { { { '[ ', B }, { lines[1], C }, { ' ]', B } } }
  end

  local vt = {}
  for i, l in ipairs(lines) do
    local prefix = (i == 1 and '┌─ ') or (i == #lines and '└─ ') or '│  '
    vt[#vt + 1] = { { prefix, B }, { l, C } }
  end
  return vt
end

--- N blank virtual lines for counterpart filler.
---@param n integer
---@return table[]
local function blank_lines(n)
  local out = {}
  for _ = 1, n do
    out[#out + 1] = { { '', 'NonText' } }
  end
  return out
end

--- Visible buffers in a tabpage, with every window showing each buffer.
---@param tab integer
---@return table<integer, { wins: integer[], width: integer }> buf -> view
local function tab_buffers(tab)
  local buffers = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_is_valid(w) then
      local buf = vim.api.nvim_win_get_buf(w)
      local view = buffers[buf]
      if not view then
        view = { wins = {}, width = vim.api.nvim_win_get_width(w) }
        buffers[buf] = view
      end
      view.wins[#view.wins + 1] = w
      view.width = math.min(view.width, vim.api.nvim_win_get_width(w))
    end
  end
  return buffers
end

--- Rebuild all comment boxes and mirrored filler for a tabpage.
--- Two passes (clear everything, then place everything) keep the result
--- idempotent regardless of which buffer owns which decoration.
---@param tab integer
local function rebuild(tab)
  highlights.ensure()
  local buffers = tab_buffers(tab)

  -- Pass 1: clear box + filler namespaces in every visible buffer.
  for buf in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.ns_box, 0, -1)
      vim.api.nvim_buf_clear_namespace(buf, M.ns_filler, 0, -1)
    end
  end

  if not config.current.inline then
    -- Signs still come from anchor marks; just ensure they exist.
    for buf in pairs(buffers) do
      anchor.ensure(buf)
    end
    return
  end

  -- Pass 2: place boxes and filler.
  for buf, view in pairs(buffers) do
    local path = session.path_for_buf(buf)
    if path then
      local sess = session.for_buf(buf)
      local comments = session.comments_for_path(sess, path)
      if #comments > 0 then
        anchor.ensure(buf)
        local width = math.min(config.current.max_width, view.width - 4)
        local line_count = vim.api.nvim_buf_line_count(buf)
        local counterparts = {}
        for _, win in ipairs(view.wins) do
          local cp = vim.wo[win].diff and diffmap.counterpart(win) or nil
          if cp and vim.api.nvim_buf_is_valid(cp.buf) then
            counterparts[cp.buf] = true
          end
        end

        for _, comment in ipairs(comments) do
          if config.visible(comment) then
            local _, end_lnum = anchor.range(buf, comment)
            local vt = box_virt_lines(comment, width)
            local box_row = math.max(0, math.min(end_lnum - 1, line_count - 1))

            vim.api.nvim_buf_set_extmark(buf, M.ns_box, box_row, 0, {
              virt_lines = vt,
              virt_lines_above = false,
            })

            for cp_buf in pairs(counterparts) do
              local m = diffmap.map(cp_buf, buf, end_lnum)
              local cp_count = vim.api.nvim_buf_line_count(cp_buf)
              local cp_row = math.max(0, math.min(m.line - 1, cp_count - 1))
              vim.api.nvim_buf_set_extmark(cp_buf, M.ns_filler, cp_row, 0, {
                virt_lines = blank_lines(#vt),
                virt_lines_above = m.placement == 'above',
              })
            end
          end
        end
      end
    end
  end
end

local scheduled = {}

--- Debounced redraw of the current tabpage.
--- Coalesces bursts of triggers into one rebuild per event-loop tick.
function M.schedule()
  local tab = vim.api.nvim_get_current_tabpage()
  if scheduled[tab] then
    return
  end
  scheduled[tab] = true
  vim.schedule(function()
    scheduled[tab] = nil
    if vim.api.nvim_tabpage_is_valid(tab) then
      rebuild(tab)
    end
  end)
end

--- Rebuild synchronously for the current tabpage (used by commands + tests).
function M.redraw()
  rebuild(vim.api.nvim_get_current_tabpage())
end

--- Test isolation.
function M._reset()
  scheduled = {}
end

return M
