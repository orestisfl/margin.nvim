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

-- Create two scratch buffers with the given line arrays, return their bufnrs.
local function make_bufs(lines_a, lines_b)
  return child.lua_get(([[(function()
    local a = vim.api.nvim_create_buf(false, true)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(a, 0, -1, false, %s)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, %s)
    return { a, b }
  end)()]]):format(vim.inspect(lines_a), vim.inspect(lines_b)))
end

-- Map source line `l` (in buf_b) to buf_a.
local function map(bufs, l)
  return child.lua_get(('D.map(%d, %d, %d)'):format(bufs[1], bufs[2], l))
end

T['map'] = MiniTest.new_set()

T['map']['context line before any hunk is exact'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 1), { line = 1, placement = 'below', exact = true })
end

T['map']['context line after a change carries offset 0'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 3), { line = 3, placement = 'below', exact = true })
end

T['map']['changed line maps within range'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'Y', 'c' })
  eq(map(b, 2), { line = 2, placement = 'below', exact = true })
end

T['map']['pure addition: added line has no counterpart, filler below'] = function()
  -- buf_a old (a,b,c); buf_b new (a,X,b,c): X is an insertion after old line 1
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'X', 'b', 'c' })
  eq(map(b, 2), { line = 1, placement = 'below', exact = false })
  -- context line after the insertion re-aligns
  eq(map(b, 3), { line = 2, placement = 'below', exact = true })
end

T['map']['pure addition at top uses above placement'] = function()
  local b = make_bufs({ 'a', 'b' }, { 'X', 'a', 'b' })
  eq(map(b, 1), { line = 1, placement = 'above', exact = false })
  eq(map(b, 2), { line = 1, placement = 'below', exact = true })
end

T['map']['pure deletion: buf_a has extra lines, offset shifts down'] = function()
  -- buf_a old (a,b,c); buf_b new (a,c): old line 2 'b' deleted
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'c' })
  eq(map(b, 1), { line = 1, placement = 'below', exact = true })
  eq(map(b, 2), { line = 3, placement = 'below', exact = true })
end

T['map']['multiple hunks accumulate offsets'] = function()
  -- two insertions in buf_b
  local b = make_bufs({ 'a', 'b', 'c', 'd' }, { 'a', 'X', 'b', 'c', 'Y', 'd' })
  eq(map(b, 1), { line = 1, placement = 'below', exact = true }) -- 'a'
  eq(map(b, 3), { line = 2, placement = 'below', exact = true }) -- 'b' after 1 insert
  eq(map(b, 4), { line = 3, placement = 'below', exact = true }) -- 'c'
  eq(map(b, 6), { line = 4, placement = 'below', exact = true }) -- 'd' after 2 inserts
end

T['map']['append at end maps to last counterpart line'] = function()
  local b = make_bufs({ 'a', 'b' }, { 'a', 'b', 'c' })
  eq(map(b, 3), { line = 2, placement = 'below', exact = false })
end

T['cache'] = MiniTest.new_set()

T['cache']['invalidates when a buffer changes'] = function()
  local b = make_bufs({ 'a', 'b', 'c' }, { 'a', 'b', 'c' })
  eq(map(b, 2), { line = 2, placement = 'below', exact = true })
  -- edit buf_b, remapping should reflect the new diff
  child.lua(('vim.api.nvim_buf_set_lines(%d, 1, 2, false, {"CHANGED"})'):format(b[2]))
  eq(map(b, 2), { line = 2, placement = 'below', exact = true })
  -- insert a line in buf_b and confirm the offset shifts
  child.lua(('vim.api.nvim_buf_set_lines(%d, 0, 0, false, {"TOP"})'):format(b[2]))
  eq(map(b, 3), { line = 2, placement = 'below', exact = true })
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
    local cp = require('margin.diffmap').counterpart(win2)
    return { has = cp ~= nil, buf = cp and cp.buf, is_buf1 = cp and cp.buf == buf1 }
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
