local MiniTest = require('mini.test')
local expect, eq = MiniTest.expect, MiniTest.expect.equality

-- string.match assertion (mini.test has no string_matches builtin).
local expect_match = MiniTest.new_expectation('string matching', function(str, pat)
  return type(str) == 'string' and str:find(pat) ~= nil
end, function(str, pat)
  return ('Pattern: %s\nObserved: %s'):format(vim.inspect(pat), vim.inspect(str))
end)

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
        Store = require('margin.store')
        S._reset()
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.tmp then vim.fn.delete(_G.tmp, 'rf') end ]])
    end,
    post_once = child.stop,
  },
})

-- Create a named file buffer at a path under root, return its bufnr.
local function open_file(rel, lines)
  return child.lua_get(([[(function()
    local p = _G.tmp .. '/%s'
    vim.fn.writefile(%s, p)
    vim.cmd('edit ' .. vim.fn.fnameescape(p))
    return vim.api.nvim_get_current_buf()
  end)()]]):format(rel, vim.inspect(lines)))
end

T['root detection'] = MiniTest.new_set()

T['root detection']['falls back to cwd without .git'] = function()
  child.lua([[ vim.fn.mkdir(_G.tmp .. '/proj', 'p'); vim.cmd('cd ' .. _G.tmp .. '/proj') ]])
  local root = child.lua_get([[ S.root_for(vim.api.nvim_get_current_buf()) ]])
  eq(root, child.lua_get([[ vim.fs.normalize(_G.tmp .. '/proj') ]]))
end

T['root detection']['uses .git marker'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/proj/.git', 'p')
    vim.fn.mkdir(_G.tmp .. '/proj/sub', 'p')
    vim.fn.writefile({'x'}, _G.tmp .. '/proj/sub/f.txt')
    vim.cmd('edit ' .. _G.tmp .. '/proj/sub/f.txt')
  ]])
  local root = child.lua_get([[ S.root_for(vim.api.nvim_get_current_buf()) ]])
  eq(root, child.lua_get([[ vim.fs.normalize(_G.tmp .. '/proj') ]]))
end

T['CRUD'] = MiniTest.new_set()

T['CRUD']['add creates a comment with correct fields'] = function()
  local buf = open_file('a.txt', { 'line one', 'line two', 'line three' })
  local c = child.lua_get(([[(function()
    local c = S.add(%d, 2, 2, 'a note')
    return c
  end)()]]):format(buf))
  eq(c.lnum, 2)
  eq(c.end_lnum, 2)
  eq(c.text, 'a note')
  eq(c.side, 'new')
  eq(c.line_text, 'line two')
  eq(c.orphaned, false)
  expect.equality(type(c.id), 'string')
  eq(c.path, 'a.txt')
end

T['CRUD']['add rejects empty text'] = function()
  local buf = open_file('a.txt', { 'x' })
  local ok = child.lua_get(([[(function()
    local c, err = S.add(%d, 1, 1, '')
    return { created = c ~= nil, err = err }
  end)()]]):format(buf))
  eq(ok.created, false)
  expect_match(ok.err, 'empty')
end

T['CRUD']['range comment stores end_lnum'] = function()
  local buf = open_file('a.txt', { 'a', 'b', 'c', 'd' })
  local c = child.lua_get(([[ S.add(%d, 2, 3, 'range') ]]):format(buf))
  eq(c.lnum, 2)
  eq(c.end_lnum, 3)
end

T['CRUD']['edit updates text, empty leaves unchanged'] = function()
  local buf = open_file('a.txt', { 'a', 'b' })
  local res = child.lua_get(([[(function()
    local c = S.add(%d, 1, 1, 'orig')
    local sess = S.for_buf(%d)
    S.edit(sess, c, 'updated')
    local after_edit = sess.comments[1].text
    S.edit(sess, c, '')
    return { after_edit = after_edit, after_empty = sess.comments[1].text }
  end)()]]):format(buf, buf))
  eq(res.after_edit, 'updated')
  eq(res.after_empty, 'updated')
end

T['CRUD']['delete removes the comment'] = function()
  local buf = open_file('a.txt', { 'a', 'b' })
  local count = child.lua_get(([[(function()
    local c = S.add(%d, 1, 1, 'x')
    local sess = S.for_buf(%d)
    S.delete(sess, c)
    return #sess.comments
  end)()]]):format(buf, buf))
  eq(count, 0)
end

T['CRUD']['clear removes all comments'] = function()
  local buf = open_file('a.txt', { 'a', 'b', 'c' })
  local count = child.lua_get(([[(function()
    S.add(%d, 1, 1, 'one')
    S.add(%d, 2, 2, 'two')
    local sess = S.for_buf(%d)
    S.clear(sess)
    return #sess.comments
  end)()]]):format(buf, buf, buf))
  eq(count, 0)
end

T['CRUD']['comments_for_path sorts by line'] = function()
  local buf = open_file('a.txt', { 'a', 'b', 'c', 'd', 'e' })
  local lnums = child.lua_get(([[(function()
    S.add(%d, 4, 4, 'later')
    S.add(%d, 1, 1, 'earlier')
    S.add(%d, 3, 3, 'middle')
    local sess = S.for_buf(%d)
    local cs = S.comments_for_path(sess, 'a.txt')
    return vim.tbl_map(function(c) return c.lnum end, cs)
  end)()]]):format(buf, buf, buf, buf))
  eq(lnums, { 1, 3, 4 })
end

T['archive'] = MiniTest.new_set()

T['archive']['add defaults archived to false'] = function()
  local buf = open_file('a.txt', { 'a' })
  local c = child.lua_get(([[ S.add(%d, 1, 1, 'x') ]]):format(buf))
  eq(c.archived, false)
end

T['archive']['set_archived toggles the flag and persists'] = function()
  local buf = open_file('a.txt', { 'a', 'b' })
  local res = child.lua_get(([[(function()
    local c = S.add(%d, 1, 1, 'note')
    local sess = S.for_buf(%d)
    S.set_archived(sess, c, true)
    S._reset()
    return S.for_buf(%d).comments[1].archived
  end)()]]):format(buf, buf, buf))
  eq(res, true)
end

T['archive']['archive_active archives only unarchived comments'] = function()
  local buf = open_file('a.txt', { 'a', 'b', 'c' })
  local res = child.lua_get(([[(function()
    local c1 = S.add(%d, 1, 1, 'one')
    S.add(%d, 2, 2, 'two')
    local sess = S.for_buf(%d)
    S.set_archived(sess, c1, true)
    local first = S.archive_active(sess)   -- only 'two' remains active
    local second = S.archive_active(sess)  -- nothing left
    return { first = first, second = second }
  end)()]]):format(buf, buf, buf))
  eq(res.first, 1)
  eq(res.second, 0)
end

T['archive']['archive_comments archives only the selected comments'] = function()
  local buf = open_file('a.txt', { 'a', 'b' })
  local res = child.lua_get(([[(function()
    local selected = S.add(%d, 1, 1, 'one')
    local other = S.add(%d, 2, 2, 'two')
    local sess = S.for_buf(%d)
    local count = S.archive_comments(sess, { selected })
    return { count = count, selected = selected.archived, other = other.archived }
  end)()]]):format(buf, buf, buf))
  eq(res.count, 1)
  eq(res.selected, true)
  eq(res.other, false)
end

T['persistence'] = MiniTest.new_set()

T['persistence']['round-trips through JSON'] = function()
  local buf = open_file('a.txt', { 'a', 'b', 'c' })
  child.lua(([[ S.add(%d, 2, 3, 'persist me\nmultiline') ]]):format(buf))

  local reloaded = child.lua_get(([[(function()
    S._reset()
    local sess = S.for_buf(%d)
    return sess.comments
  end)()]]):format(buf))
  eq(#reloaded, 1)
  eq(reloaded[1].text, 'persist me\nmultiline')
  eq(reloaded[1].lnum, 2)
  eq(reloaded[1].end_lnum, 3)
end

T['persistence']['atomic write leaves no tmp file'] = function()
  local buf = open_file('a.txt', { 'a' })
  child.lua(([[ S.add(%d, 1, 1, 'x') ]]):format(buf))
  local tmp_exists = child.lua_get([[(function()
    local root = S.root_for(vim.api.nvim_get_current_buf())
    return vim.fn.filereadable(Store.path(root) .. '.tmp')
  end)()]])
  eq(tmp_exists, 0)
  local file_exists = child.lua_get([[(function()
    local root = S.root_for(vim.api.nvim_get_current_buf())
    return vim.fn.filereadable(Store.path(root))
  end)()]])
  eq(file_exists, 1)
end

T['persistence']['unknown fields tolerated on load'] = function()
  local buf = open_file('a.txt', { 'a', 'b' })
  child.lua(([[ S.add(%d, 1, 1, 'x') ]]):format(buf))
  -- Inject an unknown field into the stored file, then reload.
  local ok = child.lua_get(([[(function()
    local root = S.root_for(%d)
    local path = Store.path(root)
    local raw = table.concat(vim.fn.readfile(path), '\n')
    local decoded = vim.json.decode(raw)
    decoded.future_field = { nested = true }
    decoded.comments[1].label = 'bug'
    vim.fn.writefile({ vim.json.encode(decoded) }, path)
    S._reset()
    local sess = S.for_buf(%d)
    return sess.comments[1].text
  end)()]]):format(buf, buf))
  eq(ok, 'x')
end

T['persistence']['wrong version major rejected'] = function()
  local buf = open_file('a.txt', { 'a' })
  child.lua(([[ S.add(%d, 1, 1, 'x') ]]):format(buf))
  local count = child.lua_get(([[(function()
    local root = S.root_for(%d)
    local path = Store.path(root)
    local decoded = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
    decoded.version = 999
    vim.fn.writefile({ vim.json.encode(decoded) }, path)
    S._reset()
    local sess = S.for_buf(%d)
    return #sess.comments
  end)()]]):format(buf, buf))
  eq(count, 0)
end

T['persistence']['store filename is stable and unique per root'] = function()
  local names = child.lua_get([[(function()
    local a = Store.filename('/home/u/projA')
    local b = Store.filename('/home/u/projB')
    local a2 = Store.filename('/home/u/projA')
    return { a = a, b = b, a2 = a2 }
  end)()]])
  eq(names.a, names.a2)
  expect.equality(names.a ~= names.b, true)
  expect_match(names.a, 'projA%-%x+%.json')
end

return T
