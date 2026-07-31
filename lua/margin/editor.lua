local M = {}

--- Trim trailing blank lines and join buffer lines into the comment body.
---@param lines string[]
---@return string
local function normalize(lines)
  local last = #lines
  while last > 0 and lines[last]:match('^%s*$') do
    last = last - 1
  end
  return table.concat(lines, '\n', 1, last)
end

--- Open the floating comment composer.
--- Saving (`:w` / `<C-s>`) submits the trimmed body; empty text aborts.
--- Closing the window without saving discards.
---@param opts { title: string, text?: string, on_submit: fun(text: string) }
function M.open(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'acwrite' -- makes :w fire BufWriteCmd instead of erroring
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'margin://compose')

  if opts.text and opts.text ~= '' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text, '\n', { plain = true }))
  end

  local width = math.min(60, math.max(20, vim.o.columns - 4))
  local height = math.min(10, math.max(3, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. opts.title .. ' ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true

  local function submit()
    local text = normalize(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if text == '' then
      return
    end
    opts.on_submit(text)
  end

  local function cancel()
    local text = normalize(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if text ~= '' then
      local choice = vim.fn.confirm('Save this comment?', '&Yes\n&No', 1)
      if choice == 1 then
        submit()
        return
      end
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<C-s>', submit, { buffer = buf, desc = 'margin: save comment' })
  vim.keymap.set('n', 'q', cancel, { buffer = buf, desc = 'margin: discard comment' })

  -- Save via :w in the scratch buffer submits without touching disk.
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      submit()
    end,
  })

  vim.cmd('startinsert')
end

return M
