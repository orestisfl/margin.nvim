local MiniTest = require('mini.test')
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua' })
      child.lua([[
        _G.tmp = vim.fs.normalize(vim.fn.tempname())
        vim.fn.mkdir(_G.tmp, 'p')
        vim.cmd('cd ' .. vim.fn.fnameescape(_G.tmp))
        require('margin.config').setup({ data_dir = _G.tmp .. '/data' })
        S = require('margin.session')
        A = require('margin.anchor')
        QF = require('margin.qf')
        S._reset(); A._reset()
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.tmp then vim.fn.delete(_G.tmp, 'rf') end ]])
    end,
    post_once = child.stop,
  },
})

local function open(lines)
  return child.lua_get(([[(function()
    vim.fn.writefile(%s, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    return vim.api.nvim_get_current_buf()
  end)()]]):format(vim.inspect(lines)))
end

T['list'] = MiniTest.new_set()

T['list']['populates quickfix sorted by path then line'] = function()
  local buf = open({ 'a', 'b', 'c', 'd', 'e' })
  child.lua(([[
    S.add(%d, 4, 4, 'later\nsecond line')
    S.add(%d, 2, 2, 'earlier')
    A.on_buf_load(%d)
    QF.list()
  ]]):format(buf, buf, buf))
  local qf = child.lua_get([[vim.fn.getqflist()]])
  eq(#qf, 2)
  eq(qf[1].lnum, 2)
  eq(qf[2].lnum, 4)
  eq(qf[2].text, 'later')
end

T['list']['prefixes orphaned comments with [stale]'] = function()
  local buf = open({ 'a', 'unique-x', 'c' })
  child.lua(([[
    S.add(%d, 2, 2, 'note')
    A.on_buf_load(%d)
    vim.fn.writefile({ 'a', 'gone', 'c' }, _G.tmp .. '/f.txt')
    vim.cmd('edit!')
    A.on_buf_load(%d)
    QF.list()
  ]]):format(buf, buf, buf))
  local qf = child.lua_get([[vim.fn.getqflist()]])
  eq(qf[1].text:sub(1, 7), '[stale]')
end

T['list']['omits archived comments unless included'] = function()
  local buf = open({ 'a', 'b', 'c' })
  child.lua(([[
    S.add(%d, 1, 1, 'active')
    local gone = S.add(%d, 3, 3, 'handed off')
    A.on_buf_load(%d)
    S.set_archived(S.for_buf(%d), gone, true)
  ]]):format(buf, buf, buf, buf))

  child.lua([[ QF.list() ]])
  local default = child.lua_get([[vim.fn.getqflist()]])
  eq(#default, 1)
  eq(default[1].text, 'active')

  child.lua([[ QF.list(true) ]])
  local all = child.lua_get([[vim.fn.getqflist()]])
  eq(#all, 2)
  local archived_line
  for _, item in ipairs(all) do
    if item.text:sub(1, 10) == '[archived]' then
      archived_line = item.text
    end
  end
  eq(archived_line, '[archived] handed off')
end

T['motions'] = MiniTest.new_set()

T['motions']['next jumps to the following comment and wraps'] = function()
  local buf = open({ 'a', 'b', 'c', 'd', 'e' })
  child.lua(([[
    S.add(%d, 2, 2, 'two')
    S.add(%d, 4, 4, 'four')
    A.on_buf_load(%d)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]]):format(buf, buf, buf))
  child.lua([[ QF.next() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 2)
  child.lua([[ QF.next() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 4)
  child.lua([[ QF.next() ]]) -- wrap
  eq(child.lua_get([[ vim.fn.line('.') ]]), 2)
end

T['motions']['prev jumps to the previous comment and wraps'] = function()
  local buf = open({ 'a', 'b', 'c', 'd', 'e' })
  child.lua(([[
    S.add(%d, 2, 2, 'two')
    S.add(%d, 4, 4, 'four')
    A.on_buf_load(%d)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
  ]]):format(buf, buf, buf))
  child.lua([[ QF.prev() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 4)
  child.lua([[ QF.prev() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 2)
  child.lua([[ QF.prev() ]]) -- wrap to last
  eq(child.lua_get([[ vim.fn.line('.') ]]), 4)
end

T['motions']['skip hidden archived comments'] = function()
  local buf = open({ 'a', 'b', 'c', 'd', 'e' })
  child.lua(([[
    S.add(%d, 2, 2, 'two')
    local four = S.add(%d, 4, 4, 'four')
    A.on_buf_load(%d)
    S.set_archived(S.for_buf(%d), four, true)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]]):format(buf, buf, buf, buf))
  child.lua([[ QF.next() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 2)
  child.lua([[ QF.next() ]])
  eq(child.lua_get([[ vim.fn.line('.') ]]), 2)
end

return T
