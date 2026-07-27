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
        Act = require('margin.actions')
        S._reset(); A._reset()
        -- Deterministic archive confirms: set _G.confirm_choice.
        _G.confirm_choice = 1
        _G.confirm_calls = 0
        vim.fn.confirm = function()
          _G.confirm_calls = _G.confirm_calls + 1
          return _G.confirm_choice
        end
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

T['archive'] = MiniTest.new_set()

T['archive']['render omits archived comments by default'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b', 'c' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    local keep = S.add(buf, 1, 1, 'keep me')
    local gone = S.add(buf, 3, 3, 'already handed off')
    A.on_buf_load(buf)
    local sess = S.for_buf(buf)
    S.set_archived(sess, gone, true)
    return {
      default = E.render(sess),
      all = E.render(sess, true),
    }
  end)()]])
  eq(res.default:find('keep me', 1, true) ~= nil, true)
  eq(res.default:find('already handed off', 1, true), nil)
  -- include_archived surfaces it with an (archived) header suffix
  eq(res.all:find('already handed off', 1, true) ~= nil, true)
  eq(res.all:find('(archived)', 1, true) ~= nil, true)
end

T['archive']['file export archives what it wrote'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'first pass')
    A.on_buf_load(buf)
    local out = _G.tmp .. '/review.md'
    Act.export(out)                       -- writes + archives (confirm yes)
    local after_first = Act.export(out)   -- nothing active left to export
    S.add(buf, 2, 2, 'second pass')       -- a fresh comment
    local second = Act.export(out)
    return {
      after_first = after_first,
      has_second = second:find('second pass', 1, true) ~= nil,
      has_first_in_second = second:find('first pass', 1, true) ~= nil,
    }
  end)()]])
  -- Second export of an all-archived session yields nothing.
  eq(res.after_first, '')
  -- A new comment exports alone; the archived one is not re-included.
  eq(res.has_second, true)
  eq(res.has_first_in_second, false)
end

T['archive']['declining the confirm keeps comments active'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'keep active')
    A.on_buf_load(buf)
    _G.confirm_choice = 2  -- No: changed my mind
    Act.export(_G.tmp .. '/review.md')
    local archived = S.for_buf(buf).comments[1].archived
    -- A second export still finds it active (nothing was archived).
    local second = Act.export(_G.tmp .. '/review.md')
    return { archived = archived, has = second:find('keep active', 1, true) ~= nil }
  end)()]])
  eq(res.archived, false)
  eq(res.has, true)
end

T['archive']['closing a preview archives only the comments it exported'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a', 'b' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'preview me')
    A.on_buf_load(buf)
    E.run()
    S.add(buf, 2, 2, 'added after preview')
    vim.cmd('quit')
    local comments = S.for_buf(buf).comments
    return {
      exported = comments[1].archived,
      added_later = comments[2].archived,
      confirms = _G.confirm_calls,
    }
  end)()]])
  eq(res.exported, true)
  eq(res.added_later, false)
  eq(res.confirms, 1)
end

T['archive']['declining the preview close confirm keeps comments active'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 1, 1, 'keep active')
    A.on_buf_load(buf)
    _G.confirm_choice = 2
    E.run()
    vim.cmd('quit')
    return S.for_buf(buf).comments[1].archived
  end)()]])
  eq(res, false)
end

T['archive']['bang preview closes without an archive prompt'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    local c = S.add(buf, 1, 1, 'archived note')
    A.on_buf_load(buf)
    local sess = S.for_buf(buf)
    S.set_archived(sess, c, true)
    E.run(nil, true)
    vim.cmd('quit')
    return { archived = c.archived, confirms = _G.confirm_calls }
  end)()]])
  eq(res.archived, true)
  eq(res.confirms, 0)
end

T['archive']['bang file export does not re-archive'] = function()
  local res = child.lua_get([[(function()
    vim.fn.writefile({ 'a' }, _G.tmp .. '/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    local c = S.add(buf, 1, 1, 'note')
    A.on_buf_load(buf)
    local sess = S.for_buf(buf)
    S.set_archived(sess, c, true)
    local md = Act.export(_G.tmp .. '/all.md', true)  -- include archived
    -- A plain re-export still finds nothing active (bang didn't unarchive).
    return { has = md:find('note', 1, true) ~= nil, plain = Act.export(_G.tmp .. '/x.md') }
  end)()]])
  eq(res.has, true)
  eq(res.plain, '')
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
