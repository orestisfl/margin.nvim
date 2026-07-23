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
        require('margin.config').setup({ data_dir = _G.tmp .. '/data', context_lines = 2 })
        vim.o.foldenable = false
        S = require('margin.session')
        A = require('margin.anchor')
        E = require('margin.export')
        S._reset(); A._reset()
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.tmp then vim.fn.delete(_G.tmp, 'rf') end ]])
    end,
    post_once = child.stop,
  },
})

T['snippet'] = MiniTest.new_set()

T['snippet']['non-diff buffer produces a fenced snippet'] = function()
  local md = child.lua_get([[(function()
    vim.fn.writefile({ 'local a = 1', 'local b = 2', 'local c = 3', 'local d = 4' }, _G.tmp .. '/m.lua')
    vim.cmd('edit ' .. _G.tmp .. '/m.lua')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 2, 2, 'name this better')
    A.on_buf_load(buf)
    return E.render(S.for_buf(buf))
  end)()]])

  local expected = table.concat({
    'I reviewed the changes. Please address the following comments.',
    '',
    '## m.lua:2',
    '',
    'name this better',
    '',
    '```lua',
    'local a = 1',
    'local b = 2',
    'local c = 3',
    'local d = 4',
    '```',
    '',
  }, '\n')
  eq(md, expected)
end

T['snippet']['multi-line body and range anchor'] = function()
  local md = child.lua_get([[(function()
    vim.fn.writefile({ 'x1', 'x2', 'x3', 'x4', 'x5' }, _G.tmp .. '/r.txt')
    vim.cmd('edit ' .. _G.tmp .. '/r.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 2, 3, 'first line\nsecond line')
    A.on_buf_load(buf)
    return E.render(S.for_buf(buf))
  end)()]])
  local expected = table.concat({
    'I reviewed the changes. Please address the following comments.',
    '',
    '## r.txt:2-3',
    '',
    'first line',
    'second line',
    '',
    '```text',
    'x1',
    'x2',
    'x3',
    'x4',
    'x5',
    '```',
    '',
  }, '\n')
  eq(md, expected)
end

T['diff'] = MiniTest.new_set()

T['diff']['live diff window produces a diff hunk'] = function()
  local md = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b', 'c', 'd', 'e', 'f' }, _G.tmp .. '/a.txt')
    vim.fn.writefile({ 'a', 'b', 'CHANGED', 'd', 'e', 'f' }, _G.tmp .. '/b.txt')
    vim.cmd('edit ' .. _G.tmp .. '/b.txt'); vim.cmd('diffthis'); vim.wo.foldenable = false
    local bn = vim.api.nvim_get_current_buf()
    vim.cmd('leftabove vsplit ' .. _G.tmp .. '/a.txt'); vim.cmd('diffthis'); vim.wo.foldenable = false
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(bn)[1])
    S.add(bn, 3, 3, 'why changed?')
    A.on_buf_load(bn)
    return E.render(S.for_buf(bn))
  end)()]])
  -- Contains a diff fence and the changed hunk with the +/- markers.
  eq(md:find('```diff', 1, true) ~= nil, true)
  eq(md:find('-c', 1, true) ~= nil, true)
  eq(md:find('+CHANGED', 1, true) ~= nil, true)
  eq(md:find('## b.txt:3', 1, true) ~= nil, true)
end

T['old side'] = MiniTest.new_set()

T['old side']['old-version header suffix'] = function()
  local md = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b', 'c' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    local c = S.add(buf, 2, 2, 'old note')
    c.side = 'old'
    S.persist(S.for_buf(buf))
    return E.render(S.for_buf(buf))
  end)()]])
  eq(md:find('## f.txt:2 (old version)', 1, true) ~= nil, true)
end

T['orphan'] = MiniTest.new_set()

T['orphan']['orphaned comment notes stale position'] = function()
  local md = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'target', 'c' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 2, 2, 'note')
    A.on_buf_load(buf)
    vim.fn.writefile({ 'a', 'changed', 'c' }, _G.tmp .. '/f.txt')
    vim.cmd('edit!')
    A.on_buf_load(buf)
    return E.render(S.for_buf(buf))
  end)()]])
  eq(md:find('(position may be stale)', 1, true) ~= nil, true)
end

T['buffer'] = MiniTest.new_set()

T['buffer']['run opens the markdown in a scratch split'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'l1', 'l2' }, _G.tmp .. '/s.txt')
    vim.cmd('edit ' .. _G.tmp .. '/s.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'note')
    A.on_buf_load(buf)
    local md = E.run()
    local cur = vim.api.nvim_get_current_buf()
    return {
      name = vim.api.nvim_buf_get_name(cur),
      filetype = vim.bo[cur].filetype,
      buftype = vim.bo[cur].buftype,
      text = table.concat(vim.api.nvim_buf_get_lines(cur, 0, -1, false), '\n') .. '\n',
      md = md,
      wins = #vim.api.nvim_list_wins(),
    }
  end)()]])
  eq(res.name, 'margin://export')
  eq(res.filetype, 'markdown')
  eq(res.buftype, 'nofile')
  eq(res.text, res.md)
  eq(res.wins, 2)
end

T['buffer']['re-export reuses the scratch buffer and window'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'l1', 'l2' }, _G.tmp .. '/s.txt')
    vim.cmd('edit ' .. _G.tmp .. '/s.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'note')
    A.on_buf_load(buf)
    E.run()
    local first = vim.api.nvim_get_current_buf()
    vim.cmd('wincmd p')
    S.add(buf, 2, 2, 'second note')
    local md = E.run()
    local cur = vim.api.nvim_get_current_buf()
    return {
      same_buf = cur == first,
      wins = #vim.api.nvim_list_wins(),
      has_second = vim.fn.stridx(
        table.concat(vim.api.nvim_buf_get_lines(cur, 0, -1, false), '\n'), 'second note') >= 0,
    }
  end)()]])
  eq(res.same_buf, true)
  eq(res.wins, 2)
  eq(res.has_second, true)
end

T['empty'] = MiniTest.new_set()

T['empty']['export of empty session returns empty string and warns'] = function()
  local res = child.lua_get([[(function()
    vim.cmd('edit ' .. _G.tmp .. '/none.txt')
    return E.run()
  end)()]])
  eq(res, '')
end

return T
