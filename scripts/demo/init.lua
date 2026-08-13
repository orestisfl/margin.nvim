local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h:h:h')

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shada = ''
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.signcolumn = 'yes'
vim.opt.cmdheight = 1
vim.opt.laststatus = 0
vim.opt.showmode = false

vim.cmd.colorscheme('habamax')
vim.api.nvim_set_hl(0, 'MarginComment', { fg = '#f5e0dc', bold = true })
vim.api.nvim_set_hl(0, 'MarginBorder', { fg = '#89b4fa' })
vim.api.nvim_set_hl(0, 'NormalFloat', { fg = '#cdd6f4', bg = '#313244' })
vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#89b4fa', bg = '#313244' })

local demo_dir = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h')
require('margin').setup({
  data_dir = demo_dir .. '/.data',
})
