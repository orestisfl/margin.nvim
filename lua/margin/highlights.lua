local M = {}

--- Default highlight links. Defined with `default = true` so user overrides win.
local links = {
  MarginSign = 'DiagnosticSignInfo',
  MarginComment = 'Comment',
  MarginBorder = 'FloatBorder',
  MarginOrphan = 'DiagnosticWarn',
  MarginArchived = 'NonText',
}

--- Define the default highlight groups.
function M.ensure()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

return M
