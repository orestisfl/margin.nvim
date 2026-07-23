local config = require('margin.config')

local M = {}

--- Current on-disk schema version. Bump the major only on incompatible changes.
M.VERSION = 1

--- Stable filename for a session, keyed by project root.
--- Basename slug keeps it human-readable; the hash guarantees uniqueness.
---@param root string absolute project root
---@return string filename (no directory)
function M.filename(root)
  local slug = vim.fn.fnamemodify(root, ':t')
  if slug == '' then
    slug = 'root'
  end
  slug = slug:gsub('[^%w%-_.]', '_')
  local hash = vim.fn.sha256(root):sub(1, 12)
  return ('%s-%s.json'):format(slug, hash)
end

--- Absolute path to a session file.
---@param root string
---@return string
function M.path(root)
  return config.data_dir() .. '/' .. M.filename(root)
end

--- Ensure the data directory exists.
local function ensure_dir()
  local dir = config.data_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end

--- Read and decode a session from disk, or nil if none/unreadable.
--- Rejects a mismatched schema major so corrupt or future files are ignored.
---@param root string
---@return margin.Session|nil
---@return string|nil error
function M.load(root)
  local path = M.path(root)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local raw = fd:read('*a')
  fd:close()

  local ok, decoded = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= 'table' then
    return nil, ('margin: could not parse session at %s'):format(path)
  end

  if math.floor(decoded.version or 0) ~= M.VERSION then
    return nil,
      ('margin: session %s has unsupported version %s'):format(path, tostring(decoded.version))
  end

  decoded.comments = decoded.comments or {}
  return decoded
end

--- Encode and atomically write a session to disk.
--- Writes to a temp file then renames so a crash mid-write never truncates.
---@param session margin.Session
---@return boolean ok
---@return string|nil error
function M.save(session)
  ensure_dir()
  local path = M.path(session.root)
  local tmp = path .. '.tmp'

  local ok, encoded = pcall(vim.json.encode, session)
  if not ok then
    return false, ('margin: could not encode session: %s'):format(encoded)
  end

  local fd, open_err = io.open(tmp, 'w')
  if not fd then
    return false, ('margin: could not open %s: %s'):format(tmp, tostring(open_err))
  end
  fd:write(encoded)
  fd:close()

  local rok, rerr = vim.uv.fs_rename(tmp, path)
  if not rok then
    os.remove(tmp)
    return false, ('margin: could not rename %s -> %s: %s'):format(tmp, path, tostring(rerr))
  end
  return true
end

--- Delete a session file from disk (used by clear-all).
---@param root string
function M.delete(root)
  os.remove(M.path(root))
end

return M
