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
        S._reset(); A._reset()
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.tmp then vim.fn.delete(_G.tmp, 'rf') end ]])
    end,
    post_once = child.stop,
  },
})

-- Open a named file buffer under root, add a comment, run initial anchoring.
local function setup_comment(lines, lnum, endl, text)
  return child.lua_get(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile(%s, p)
    vim.cmd('edit ' .. vim.fn.fnameescape(p))
    local buf = vim.api.nvim_get_current_buf()
    local c = S.add(buf, %d, %d, %s)
    A.on_buf_load(buf)
    return { buf = buf, id = c.id }
  end)()]]):format(vim.inspect(lines), lnum, endl, vim.inspect(text)))
end

local function comment_state(id)
  return child.lua_get(([[(function()
    local sess = S.for_buf(vim.api.nvim_get_current_buf())
    for _, c in ipairs(sess.comments) do
      if c.id == '%s' then return c end
    end
  end)()]]):format(id))
end

T['extmark tracking'] = MiniTest.new_set()

T['extmark tracking']['shifts down when a line is inserted above'] = function()
  local h = setup_comment({ 'a', 'b', 'c' }, 2, 2, 'note')
  child.lua(('vim.api.nvim_buf_set_lines(%d, 0, 0, false, {"TOP"})'):format(h.buf))
  local r = child.lua_get(([[(function()
    local sess = S.for_buf(%d)
    local c = sess.comments[1]
    local a, b = A.range(%d, c)
    return { a = a, b = b }
  end)()]]):format(h.buf, h.buf))
  eq(r.a, 3)
  eq(r.b, 3)
end

T['extmark tracking']['expands when a line is inserted inside the range'] = function()
  local h = setup_comment({ 'a', 'b', 'c', 'd' }, 2, 3, 'note')
  child.lua(('vim.api.nvim_buf_set_lines(%d, 2, 2, false, {"MID"})'):format(h.buf))
  local r = child.lua_get(([[(function()
    local sess = S.for_buf(%d)
    local a, b = A.range(%d, sess.comments[1])
    return { a = a, b = b }
  end)()]]):format(h.buf, h.buf))
  eq(r.a, 2)
  eq(r.b, 4)
end

T['orphaning'] = MiniTest.new_set()

T['orphaning']['range deletion invalidates -> orphaned on persist'] = function()
  local h = setup_comment({ 'a', 'b', 'c' }, 2, 2, 'note')
  -- delete the commented line entirely
  child.lua(('vim.api.nvim_buf_set_lines(%d, 1, 2, false, {})'):format(h.buf))
  -- persist triggers the sync hook which reads details.invalid
  child.lua(('S.persist(S.for_buf(%d))'):format(h.buf))
  local c = comment_state(h.id)
  eq(c.orphaned, true)
end

T['re-anchoring'] = MiniTest.new_set()

T['re-anchoring']['exact match at stored line keeps position'] = function()
  local h = setup_comment({ 'alpha', 'beta', 'gamma' }, 2, 2, 'note')
  child.lua(('A.on_buf_load(%d)'):format(h.buf))
  local c = comment_state(h.id)
  eq(c.lnum, 2)
  eq(c.orphaned, false)
end

T['re-anchoring']['relocates to a moved unique match within radius'] = function()
  -- Simulate external edit: reload file with the commented line shifted down.
  local h = setup_comment({ 'alpha', 'beta', 'gamma' }, 2, 2, 'note')
  child.lua(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile({ 'x0', 'x1', 'alpha', 'beta', 'gamma' }, p)
    vim.cmd('edit! ' .. vim.fn.fnameescape(p))
    A.on_buf_load(vim.api.nvim_get_current_buf())
  end)()]]):format())
  local c = comment_state(h.id)
  eq(c.lnum, 4) -- 'beta' moved from line 2 to line 4
  eq(c.orphaned, false)
end

T['re-anchoring']['ambiguous match -> orphaned'] = function()
  local h = setup_comment({ 'x', 'dup', 'y' }, 2, 2, 'note')
  child.lua(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile({ 'dup', 'a', 'b', 'dup' }, p)
    vim.cmd('edit! ' .. vim.fn.fnameescape(p))
    A.on_buf_load(vim.api.nvim_get_current_buf())
  end)()]]):format())
  local c = comment_state(h.id)
  eq(c.orphaned, true)
end

T['re-anchoring']['no match -> orphaned'] = function()
  local h = setup_comment({ 'x', 'unique-line', 'y' }, 2, 2, 'note')
  child.lua(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile({ 'completely', 'different', 'content' }, p)
    vim.cmd('edit! ' .. vim.fn.fnameescape(p))
    A.on_buf_load(vim.api.nvim_get_current_buf())
  end)()]]):format())
  local c = comment_state(h.id)
  eq(c.orphaned, true)
end

T['re-anchoring']['un-orphans when the line reappears'] = function()
  local h = setup_comment({ 'x', 'target', 'y' }, 2, 2, 'note')
  -- lose it
  child.lua(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile({ 'nothing', 'here', 'now' }, p)
    vim.cmd('edit! ' .. vim.fn.fnameescape(p))
    A.on_buf_load(vim.api.nvim_get_current_buf())
  end)()]]):format())
  eq(comment_state(h.id).orphaned, true)
  -- bring it back
  child.lua(([[(function()
    local p = _G.tmp .. '/f.txt'
    vim.fn.writefile({ 'x', 'target', 'y' }, p)
    vim.cmd('edit! ' .. vim.fn.fnameescape(p))
    A.reanchor_all()
  end)()]]):format())
  eq(comment_state(h.id).orphaned, false)
end

return T
