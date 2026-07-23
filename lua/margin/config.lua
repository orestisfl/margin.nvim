---@class margin.Config
---@field inline boolean          -- render virt_lines comment boxes
---@field max_width integer       -- comment box wrap width
---@field context_lines integer   -- export context / hunk ctxlen
---@field sign_text string        -- sign column indicator
---@field data_dir string|nil     -- override stdpath('data')/margin

local M = {}

---@type margin.Config
local defaults = {
  inline = true,
  max_width = 80,
  context_lines = 3,
  sign_text = '┃',
  data_dir = nil,
}

---@type margin.Config
M.current = vim.deepcopy(defaults)

--- Validate and merge user options into the active config.
--- Unknown keys are an error so typos surface immediately.
---@param opts margin.Config|nil
---@return margin.Config
function M.setup(opts)
  opts = opts or {}

  for key in pairs(opts) do
    if defaults[key] == nil and key ~= 'data_dir' then
      error(('margin: unknown config key %q'):format(key), 0)
    end
  end

  local merged = vim.tbl_extend('force', vim.deepcopy(defaults), opts)

  vim.validate('inline', merged.inline, 'boolean')
  vim.validate('max_width', merged.max_width, 'number')
  vim.validate('context_lines', merged.context_lines, 'number')
  vim.validate('sign_text', merged.sign_text, 'string')
  vim.validate('data_dir', merged.data_dir, 'string', true)

  M.current = merged
  return merged
end

--- Resolve the directory sessions are stored in.
---@return string
function M.data_dir()
  return M.current.data_dir or (vim.fn.stdpath('data') .. '/margin')
end

return M
