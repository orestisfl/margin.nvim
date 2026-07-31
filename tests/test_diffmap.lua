local MiniTest = require('mini.test')
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua' })
      child.lua([[
        D = require('margin.diffmap')
        D._reset()
      ]])
    end,
    post_once = child.stop,
  },
})

-- Create two scratch buffers from line arrays.
local function make_bufs(lines_a, lines_b)
  return child.lua_get(([[(function()
    local a = vim.api.nvim_create_buf(false, true)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(a, 0, -1, false, %s)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, %s)
    return { a, b }
  end)()]]):format(vim.inspect(lines_a), vim.inspect(lines_b)))
end

-- Map a line in buf_b to buf_a.
local function map(bufs, l)
  return child.lua_get(('D.map(%d, %d, %d)'):format(bufs[1], bufs[2], l))
end

T['map'] = MiniTest.new_set()

T['map']['context line before any hunk keeps its line'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 1), { line = 1, placement = 'below' })
end

T['map']['context line after a change carries offset 0'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 3), { line = 3, placement = 'below' })
end

T['map']['changed line maps within range'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 2), { line = 2, placement = 'below' })
end

T['map']['pure addition: added line has no counterpart, filler below'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'X', 'b', 'c' })
  eq(map(b, 2), { line = 1, placement = 'below' })
  eq(map(b, 3), { line = 2, placement = 'below' })
end

T['map']['pure addition at top uses above placement'] = function()
  local b = make_bufs({ 'a', 'b' }, { 'X', 'a', 'b' })
  eq(map(b, 1), { line = 1, placement = 'above' })
  eq(map(b, 2), { line = 1, placement = 'below' })
end

T['map']['pure deletion: buf_a has extra lines, offset shifts down'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'c' })
  eq(map(b, 1), { line = 1, placement = 'below' })
  eq(map(b, 2), { line = 3, placement = 'below' })
end

T['map']['multiple hunks accumulate offsets'] = function()
  local b = make_bufs({ 'a', 'b', 'c', 'd' }, { 'a', 'X', 'b', 'c', 'Y', 'd' })
  eq(map(b, 1), { line = 1, placement = 'below' })
  eq(map(b, 3), { line = 2, placement = 'below' })
  eq(map(b, 4), { line = 3, placement = 'below' })
  eq(map(b, 6), { line = 4, placement = 'below' })
end

T['map']['append at end maps to last counterpart line'] = function()
  local b = make_bufs({ 'a', 'b' }, { 'a', 'b', 'c' })
  eq(map(b, 3), { line = 2, placement = 'below' })
end

T['cache'] = MiniTest.new_set()

T['cache']['invalidates when a buffer changes'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'b', 'c' })
  eq(map(b, 2), { line = 2, placement = 'below' })
  child.lua(('vim.api.nvim_buf_set_lines(%d, 1, 2, false, {"CHANGED"})'):format(b[2]))
  eq(map(b, 2), { line = 2, placement = 'below' })
  child.lua(('vim.api.nvim_buf_set_lines(%d, 0, 0, false, {"TOP"})'):format(b[2]))
  eq(map(b, 3), { line = 2, placement = 'below' })
end

T['counterpart'] = MiniTest.new_set()

T['counterpart']['finds the other diff window'] = function()
  local res = child.lua_get([[(function()
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a', 'b', 'c' })
    local buf1 = vim.api.nvim_get_current_buf()
    vim.cmd('diffthis')
    vim.cmd('vnew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a', 'X', 'c' })
    local buf2 = vim.api.nvim_get_current_buf()
    vim.cmd('diffthis')
    local win2 = vim.api.nvim_get_current_win()
    local cp_buf = require('margin.diffmap').counterpart(win2)
    return { has = cp_buf ~= nil, is_buf1 = cp_buf == buf1 }
  end)()]])
  eq(res.has, true)
  eq(res.is_buf1, true)
end

T['counterpart']['nil for a non-diff window'] = function()
  local res = child.lua_get([[(function()
    vim.cmd('enew')
    local win = vim.api.nvim_get_current_win()
    return require('margin.diffmap').counterpart(win)
  end)()]])
  eq(res, vim.NIL)
end

return T
