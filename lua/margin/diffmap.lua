local M = {}

--- Full buffer contents as one newline-terminated string, ready for
--- `vim.text.diff` (which treats a missing final newline as a change).
---@param buf integer
---@return string
function M.buf_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, '\n') .. '\n'
end

--- Diff algorithm from 'diffopt', defaulting to histogram.
---@return string
local function diff_algorithm()
  for _, opt in ipairs(vim.split(vim.o.diffopt, ',', { plain = true })) do
    local alg = opt:match('^algorithm:(.+)$')
    if alg then
      return alg
    end
  end
  return 'histogram'
end

--- The counterpart diff window for a diff window in the same tabpage.
--- First other window with 'diff' set and a different buffer; nil otherwise.
--- With more than two diff windows (3-way merge) the first is chosen.
---@param win integer
---@return { win: integer, buf: integer }|nil
function M.counterpart(win)
  if not vim.api.nvim_win_is_valid(win) or not vim.wo[win].diff then
    return nil
  end
  local this_buf = vim.api.nvim_win_get_buf(win)
  local tab = vim.api.nvim_win_get_tabpage(win)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if w ~= win and vim.wo[w].diff then
      local b = vim.api.nvim_win_get_buf(w)
      if b ~= this_buf then
        return { win = w, buf = b }
      end
    end
  end
  return nil
end

---@type table<string, table>
local cache = {}

--- Diff hunks between two buffers, cached per changedtick pair.
--- Hunks are {start_a, count_a, start_b, count_b} with buf_a as the "to" side.
---@param buf_a integer counterpart / target buffer (text_a)
---@param buf_b integer source buffer (text_b)
---@return integer[][]
local function hunks_between(buf_a, buf_b)
  local ta = vim.api.nvim_buf_get_changedtick(buf_a)
  local tb = vim.api.nvim_buf_get_changedtick(buf_b)
  local key = ('%d:%d:%d:%d'):format(buf_a, ta, buf_b, tb)
  local hit = cache[key]
  if hit then
    return hit.hunks
  end

  local hunks = vim.text.diff(M.buf_text(buf_a), M.buf_text(buf_b), {
    result_type = 'indices',
    linematch = true,
    indent_heuristic = true,
    algorithm = diff_algorithm(),
  }) --[[@as integer[][] ]]

  cache = { [key] = { hunks = hunks } }
  return hunks
end

--- Map a 1-based line in `buf_b` to an anchor line in `buf_a`.
--- Returns the target line and whether filler goes `above` or `below` it.
--- `above` is used only for an addition before line 1 of buf_a.
---@param buf_a integer target buffer
---@param buf_b integer source buffer (line is in this buffer)
---@param line integer 1-based line in buf_b
---@return { line: integer, placement: "above"|"below", exact: boolean }
function M.map(buf_a, buf_b, line)
  local hunks = hunks_between(buf_a, buf_b)
  local offset = 0

  for _, h in ipairs(hunks) do
    local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
    if cb > 0 then
      local hb_start, hb_end = sb, sb + cb - 1
      if line < hb_start then
        break -- source line is before this and all following hunks
      elseif line <= hb_end then
        if ca > 0 then
          -- changed region: map proportionally, clamp into the A range
          return {
            line = math.min(sa + (line - sb), sa + ca - 1),
            placement = 'below',
            exact = true,
          }
        else
          -- pure addition in buf_b: no counterpart line exists
          if sa == 0 then
            return { line = 1, placement = 'above', exact = false }
          end
          return { line = sa, placement = 'below', exact = false }
        end
      else
        offset = offset + (ca - cb) -- hunk strictly above the source line
      end
    elseif sb < line then
      -- deletion from buf_b (buf_a has extra lines), sitting above the line
      offset = offset + (ca - cb)
    end
  end

  return { line = line + offset, placement = 'below', exact = true }
end

--- Clear the hunk cache (test isolation).
function M._reset()
  cache = {}
end

return M
