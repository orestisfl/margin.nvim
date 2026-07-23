-- Minimal init for headless test runs.
-- Wires margin.nvim and the mini.test dev dependency onto the runtimepath.

local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h:h')

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. '/deps/mini.nvim')

vim.opt.swapfile = false
vim.opt.shada = ''

require('mini.test').setup()
