-- Headless test entry point: runs the suites through the stdout reporter, then
-- exits nonzero if any case failed so scripts and pre-commit can gate on it.
-- Set MARGIN_TEST_FILE to run a single suite instead of all of them.

local MiniTest = require('mini.test')

local file = vim.env.MARGIN_TEST_FILE
local base = MiniTest.gen_reporter.stdout({ group_depth = (file and file ~= '') and 2 or 1 })

local n_fail = 0
local reporter = vim.tbl_extend('force', base, {
  finish = function(...)
    if base.finish then
      base.finish(...)
    end
    for _, case in ipairs(MiniTest.current.all_cases or {}) do
      local exec = case.exec
      if type(exec) == 'table' and exec.fails and #exec.fails > 0 then
        n_fail = n_fail + 1
      end
    end
  end,
})

if file and file ~= '' then
  MiniTest.run_file(file, { execute = { reporter = reporter } })
else
  MiniTest.run({ execute = { reporter = reporter } })
end

vim.cmd(n_fail > 0 and ('cquit ' .. n_fail) or 'qall!')
