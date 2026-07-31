if vim.g.loaded_margin then
  return
end
vim.g.loaded_margin = true

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('margin.nvim requires Neovim 0.12+', vim.log.levels.ERROR)
  return
end

local margin = require('margin')

local subcommands = {
  comment = function(a)
    margin.comment({ line1 = a.line1, line2 = a.line2 })
  end,
  edit = margin.edit,
  delete = margin.delete,
  list = function(a)
    margin.list(a.bang)
  end,
  export = function(a)
    margin.export(a.fargs[2], a.bang)
  end,
  archive = margin.archive,
  unarchive = margin.unarchive,
  inline = margin.toggle_inline,
  archived = margin.toggle_archived,
  clear = margin.clear,
}

vim.api.nvim_create_user_command('Margin', function(a)
  local sub = a.fargs[1]
  if not sub or not subcommands[sub] then
    vim.notify('margin: unknown subcommand ' .. tostring(sub), vim.log.levels.ERROR)
    return
  end
  -- Ensure autocmds are installed on first use even without setup().
  require('margin.autocmds').setup()
  subcommands[sub](a)
end, {
  nargs = '+',
  range = true,
  bang = true,
  desc = 'margin.nvim',
  complete = function(arglead, cmdline)
    -- Only complete the first argument (the subcommand name).
    if cmdline:match('^%s*Margin!?%s+%S*$') then
      local names = vim.tbl_keys(subcommands)
      table.sort(names)
      return vim.tbl_filter(function(n)
        return n:find(arglead, 1, true) == 1
      end, names)
    end
    return {}
  end,
})

local maps = {
  ['(margin-comment)'] = {
    modes = { 'n', 'x' },
    fn = function()
      local mode = vim.fn.mode()
      if mode == 'v' or mode == 'V' or mode == '\22' then
        -- exit visual so '< '> marks are set, then comment on the range
        vim.cmd('normal! \27')
        local line1 = vim.fn.line("'<")
        local line2 = vim.fn.line("'>")
        margin.comment({ line1 = line1, line2 = line2 })
      else
        margin.comment()
      end
    end,
  },
  ['(margin-edit)'] = {
    modes = { 'n' },
    fn = margin.edit,
  },
  ['(margin-delete)'] = {
    modes = { 'n' },
    fn = margin.delete,
  },
  ['(margin-list)'] = {
    modes = { 'n' },
    fn = margin.list,
  },
  ['(margin-archive)'] = {
    modes = { 'n' },
    fn = margin.archive,
  },
  ['(margin-unarchive)'] = {
    modes = { 'n' },
    fn = margin.unarchive,
  },
  ['(margin-archived)'] = {
    modes = { 'n' },
    fn = margin.toggle_archived,
  },
  ['(margin-export)'] = {
    modes = { 'n' },
    fn = margin.export,
  },
  ['(margin-next)'] = {
    modes = { 'n' },
    fn = margin.next,
  },
  ['(margin-prev)'] = {
    modes = { 'n' },
    fn = margin.prev,
  },
}

-- Every mapping installs the autocmds first, so lazy-loading on any of them
-- (e.g. keys = { { ']m', '<Plug>(margin-next)' } }) activates margin fully.
for lhs, spec in pairs(maps) do
  local fn = spec.fn
  vim.keymap.set(spec.modes, '<Plug>' .. lhs, function()
    require('margin.autocmds').setup()
    fn()
  end, { desc = 'margin ' .. lhs })
end
