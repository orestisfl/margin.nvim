local MiniTest = require('mini.test')
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua', '--cmd', 'set lines=24 columns=100' })
      child.lua([[
        _G.tmp = vim.fs.normalize(vim.fn.tempname())
        vim.fn.mkdir(_G.tmp, 'p')
        vim.cmd('cd ' .. vim.fn.fnameescape(_G.tmp))
        require('margin.config').setup({ data_dir = _G.tmp .. '/data' })
        vim.o.foldenable = false
        S = require('margin.session')
        A = require('margin.anchor')
        R = require('margin.render')
        S._reset(); A._reset(); R._reset()
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.tmp then vim.fn.delete(_G.tmp, 'rf') end ]])
    end,
    post_once = child.stop,
  },
})

-- Open a two-pane vertical diff, folds off, return a.txt's bufnr.
-- :vsplit puts b.txt on the left, so a.txt is the 'right' pane in panes().
local function open_diff(lines_a, lines_b)
  return child.lua_get(([[(function()
    vim.fn.writefile(%s, _G.tmp .. '/a.txt')
    vim.fn.writefile(%s, _G.tmp .. '/b.txt')
    vim.cmd('edit ' .. _G.tmp .. '/a.txt'); vim.cmd('diffthis'); vim.wo.foldenable = false
    local ba = vim.api.nvim_get_current_buf()
    vim.cmd('vsplit ' .. _G.tmp .. '/b.txt'); vim.cmd('diffthis'); vim.wo.foldenable = false
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(ba)[1])
    return ba
  end)()]]):format(vim.inspect(lines_a), vim.inspect(lines_b)))
end

-- Screenshot text rows split at the vertical separator into {left, right}.
local function panes()
  child.cmd('redraw')
  local ss = child.get_screenshot()
  local rows = {}
  for i = 1, #ss.text do
    rows[i] = table.concat(ss.text[i])
  end
  -- separator column from the first content row
  local sep = rows[1]:find('│')
  local out = {}
  for i, row in ipairs(rows) do
    if sep then
      out[i] = { left = row:sub(1, sep - 1), right = row:sub(sep + 1) }
    else
      out[i] = { left = row, right = '' }
    end
  end
  return out
end

-- Screen row (1-based) on which `text` appears in a given pane, or nil.
local function row_of(rows, pane, text)
  for i, r in ipairs(rows) do
    if r[pane] and r[pane]:find(text, 1, true) then
      return i
    end
  end
  return nil
end

-- Assert every shared marker sits on the same screen row in both panes.
local function assert_aligned(rows, markers)
  for _, m in ipairs(markers) do
    local l = row_of(rows, 'left', m)
    local r = row_of(rows, 'right', m)
    eq(
      { marker = m, left = l, right = r, aligned = l == r },
      { marker = m, left = l, right = r, aligned = true }
    )
  end
end

T['alignment'] = MiniTest.new_set()

T['alignment']['comment on a context line keeps panes aligned'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc', 'dd', 'ee' }, { 'aa', 'XX', 'cc', 'dd', 'ee' })
  child.lua(('S.add(%d, 4, 4, "note here"); A.on_buf_load(%d); R.redraw()'):format(ba, ba))
  local rows = panes()
  assert_aligned(rows, { 'aa', 'cc', 'dd', 'ee' })
end

T['alignment']['comment on an added line coexists with native filler'] = function()
  -- b has an extra line 'INS' that a lacks: an addition on the a-side counterpart.
  local ba = open_diff({ 'aa', 'bb', 'cc' }, { 'aa', 'INS', 'bb', 'cc' })
  child.lua(('S.add(%d, 1, 1, "top note"); A.on_buf_load(%d); R.redraw()'):format(ba, ba))
  local rows = panes()
  assert_aligned(rows, { 'aa', 'bb', 'cc' })
end

T['alignment']['comment at top of buffer stays aligned'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc' }, { 'aa', 'bb', 'cc' })
  child.lua(('S.add(%d, 1, 1, "first line note"); A.on_buf_load(%d); R.redraw()'):format(ba, ba))
  local rows = panes()
  assert_aligned(rows, { 'bb', 'cc' })
end

T['alignment']['multiple comments stay aligned'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc', 'dd', 'ee' }, { 'aa', 'bb', 'cc', 'dd', 'ee' })
  child.lua(([[
    S.add(%d, 2, 2, "note two")
    S.add(%d, 4, 4, "note four")
    A.on_buf_load(%d); R.redraw()
  ]]):format(ba, ba, ba))
  local rows = panes()
  assert_aligned(rows, { 'aa', 'cc', 'ee' })
end

T['toggle_inline'] = MiniTest.new_set()

T['toggle_inline']['off removes boxes, on restores, signs persist'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc' }, { 'aa', 'bb', 'cc' })
  child.lua(('S.add(%d, 2, 2, "toggle note"); A.on_buf_load(%d); R.redraw()'):format(ba, ba))

  local with_box = row_of(panes(), 'right', 'toggle note')
  eq(with_box ~= nil, true)

  child.lua([[ require('margin.actions').toggle_inline() ]])
  local rows_off = panes()
  eq(row_of(rows_off, 'right', 'toggle note'), nil)
  eq(row_of(rows_off, 'right', '┃') ~= nil, true)

  child.lua([[ require('margin.actions').toggle_inline() ]])
  eq(row_of(panes(), 'right', 'toggle note') ~= nil, true)
end

T['deduplication'] = MiniTest.new_set()

T['deduplication']['one buffer in two windows gets one box extmark'] = function()
  local count = child.lua_get([[(function()
    vim.fn.writefile({ 'aa', 'bb', 'cc' }, _G.tmp .. '/shared.txt')
    vim.cmd('edit ' .. _G.tmp .. '/shared.txt')
    local buf = vim.api.nvim_get_current_buf()
    S.add(buf, 2, 2, 'shown once')
    A.on_buf_load(buf)
    vim.cmd('split')
    R.redraw()
    return #vim.api.nvim_buf_get_extmarks(buf, R.ns_box, 0, -1, {})
  end)()]])

  eq(count, 1)
end

T['archive'] = MiniTest.new_set()

T['archive']['hides archived comments by default, sign gone too'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc' }, { 'aa', 'bb', 'cc' })
  child.lua(('S.add(%d, 2, 2, "handed off"); A.on_buf_load(%d); R.redraw()'):format(ba, ba))
  eq(row_of(panes(), 'right', 'handed off') ~= nil, true)
  eq(row_of(panes(), 'right', '┃') ~= nil, true)

  child.lua(([[
    local sess = S.for_buf(%d)
    S.set_archived(sess, sess.comments[1], true)
    R.redraw()
  ]]):format(ba))
  local rows = panes()
  eq(row_of(rows, 'right', 'handed off'), nil)
  eq(row_of(rows, 'right', '┃'), nil)
end

T['archive']['show_archived renders the full dimmed box with a tag'] = function()
  local ba = open_diff({ 'aa', 'bb', 'cc' }, { 'aa', 'bb', 'cc' })
  child.lua(([[
    S.add(%d, 2, 2, "handed off"); A.on_buf_load(%d)
    local sess = S.for_buf(%d)
    S.set_archived(sess, sess.comments[1], true)
    require('margin.actions').toggle_archived()
  ]]):format(ba, ba, ba))
  local rows = panes()
  eq(row_of(rows, 'right', 'handed off') ~= nil, true)
  eq(row_of(rows, 'right', 'archived') ~= nil, true)
  eq(row_of(rows, 'right', '┃') ~= nil, true)
end

T['orphan'] = MiniTest.new_set()

T['orphan']['renders a stale line, not a box'] = function()
  local ba = open_diff({ 'aa', 'unique-target', 'cc' }, { 'aa', 'unique-target', 'cc' })
  child.lua(('S.add(%d, 2, 2, "will orphan"); A.on_buf_load(%d)'):format(ba, ba))
  child.lua(([[
    vim.fn.writefile({ 'aa', 'gone', 'cc' }, _G.tmp .. '/a.txt')
    vim.cmd('edit!'); vim.wo.foldenable = false
    A.on_buf_load(%d); R.redraw()
  ]]):format(ba))
  local rows = panes()
  eq(row_of(rows, 'right', 'stale') ~= nil, true)
end

return T
