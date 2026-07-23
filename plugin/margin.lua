if vim.g.loaded_margin then
  return
end
vim.g.loaded_margin = true

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('margin.nvim requires Neovim 0.12+', vim.log.levels.ERROR)
  return
end

local subcommands = {
  comment = function(a)
    require('margin.actions').comment({ line1 = a.line1, line2 = a.line2 })
  end,
  edit = function()
    require('margin.actions').edit()
  end,
  delete = function()
    require('margin.actions').delete()
  end,
  list = function()
    require('margin.qf').list()
  end,
  export = function(a)
    require('margin.export').run(a.fargs[2])
  end,
  inline = function()
    require('margin.actions').toggle_inline()
  end,
  clear = function()
    require('margin.actions').clear()
  end,
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
  desc = 'margin.nvim',
  complete = function(arglead, cmdline)
    -- Only complete the first argument (the subcommand name).
    if cmdline:match('^%s*Margin%s+%S*$') then
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
        require('margin.autocmds').setup()
        require('margin.actions').comment({ line1 = line1, line2 = line2 })
      else
        require('margin.autocmds').setup()
        require('margin.actions').comment()
      end
    end,
  },
  ['(margin-edit)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.actions').edit()
    end,
  },
  ['(margin-delete)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.actions').delete()
    end,
  },
  ['(margin-list)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.qf').list()
    end,
  },
  ['(margin-export)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.export').run()
    end,
  },
  ['(margin-next)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.qf').next()
    end,
  },
  ['(margin-prev)'] = {
    modes = { 'n' },
    fn = function()
      require('margin.qf').prev()
    end,
  },
}

for lhs, spec in pairs(maps) do
  vim.keymap.set(spec.modes, '<Plug>' .. lhs, spec.fn, { desc = 'margin ' .. lhs })
end
