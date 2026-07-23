local M = {}

--- Default highlight links. Defined with `default = true` so user overrides win.
local links = {
  MarginSign = 'DiagnosticSignInfo',
  MarginComment = 'Comment',
  MarginBorder = 'FloatBorder',
  MarginOrphan = 'DiagnosticWarn',
}

local done = false

--- Define margin's highlight groups once. Safe to call repeatedly.
function M.ensure()
  if done then
    return
  end
  done = true
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

return M
