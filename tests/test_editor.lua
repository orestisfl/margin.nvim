local MiniTest = require('mini.test')
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua' })
      child.lua([[
        Editor = require('margin.editor')
        _G.submissions = {}
        _G.confirm_calls = {}
        _G.confirm_choice = 1
        vim.fn.confirm = function(message, choices, default)
          table.insert(_G.confirm_calls, {
            message = message,
            choices = choices,
            default = default,
          })
          return _G.confirm_choice
        end
      ]])
    end,
    post_once = child.stop,
  },
})

local function open(text)
  child.lua(
    [[
      Editor.open({
        title = 'test',
        text = ...,
        on_submit = function(value)
          table.insert(_G.submissions, value)
        end,
      })
    ]],
    { text }
  )
  child.ensure_normal_mode()
end

local function state()
  return child.lua_get([[
    {
      submissions = _G.submissions,
      confirm_calls = _G.confirm_calls,
      window_count = #vim.api.nvim_list_wins(),
    }
  ]])
end

T['q discards an empty comment without confirmation'] = function()
  open(nil)
  child.type_keys('q')

  local result = state()
  eq(result.submissions, {})
  eq(result.confirm_calls, {})
  eq(result.window_count, 1)
end

T['q saves a non-empty comment when confirmation is accepted'] = function()
  open('keep me')
  child.type_keys('q')

  local result = state()
  eq(result.submissions, { 'keep me' })
  eq(result.confirm_calls, {
    {
      message = 'Save this comment?',
      choices = '&Yes\n&No',
      default = 1,
    },
  })
  eq(result.window_count, 1)
end

T['q discards a non-empty comment when confirmation is declined'] = function()
  child.lua([[_G.confirm_choice = 2]])
  open('discard me')
  child.type_keys('q')

  local result = state()
  eq(result.submissions, {})
  eq(#result.confirm_calls, 1)
  eq(result.window_count, 1)
end

T['writing an empty comment discards it without submission'] = function()
  open(nil)
  child.cmd('write')

  local result = state()
  eq(result.submissions, {})
  eq(result.confirm_calls, {})
  eq(result.window_count, 1)
end

T['writing a non-empty comment still submits it'] = function()
  open('save me')
  child.cmd('write')

  local result = state()
  eq(result.submissions, { 'save me' })
  eq(result.confirm_calls, {})
  eq(result.window_count, 1)
end

return T
