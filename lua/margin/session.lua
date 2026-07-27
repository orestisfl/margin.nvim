local store = require('margin.store')

---@class margin.Comment
---@field id string
---@field path string
---@field side "new"|"old"
---@field lnum integer
---@field end_lnum integer
---@field text string
---@field line_text string
---@field created_at string
---@field orphaned boolean
---@field archived boolean

---@class margin.Session
---@field version integer
---@field root string
---@field created_at string
---@field updated_at string
---@field comments margin.Comment[]

local M = {}

--- Loaded sessions keyed by absolute root. One session per project.
---@type table<string, margin.Session>
local cache = {}

--- Change subscribers, invoked as fn(session, event) after each mutation.
---@type fun(session: margin.Session, event: string)[]
local subscribers = {}

--- Position-sync hooks, invoked before each persist to flush live extmark
--- positions back into the stored comments.
---@type fun(session: margin.Session)[]
local sync_hooks = {}

local id_counter = 0

--- ISO 8601 timestamp in UTC.
---@return string
local function now_iso()
  return os.date('!%Y-%m-%dT%H:%M:%SZ') --[[@as string]]
end

--- Opaque unique comment id (time + monotonic counter).
---@return string
local function new_id()
  id_counter = id_counter + 1
  return ('%d-%d'):format(os.time(), id_counter)
end

--- Register a callback fired after every mutation.
---@param fn fun(session: margin.Session, event: string)
function M.on_change(fn)
  table.insert(subscribers, fn)
end

--- Register a hook that syncs live positions into comments before persist.
---@param fn fun(session: margin.Session)
function M.add_sync_hook(fn)
  table.insert(sync_hooks, fn)
end

---@param session margin.Session
---@param event string
local function emit(session, event)
  for _, fn in ipairs(subscribers) do
    pcall(fn, session, event)
  end
end

--- Detect the project root for a buffer. Git is a marker only.
---@param buf integer
---@return string
function M.root_for(buf)
  local root = vim.fs.root(buf, '.git')
  if root and root ~= '' then
    return vim.fs.normalize(root)
  end
  return vim.fs.normalize(vim.fn.getcwd())
end

--- Get (loading or lazily creating) the session for a root.
---@param root string absolute root
---@return margin.Session
function M.get(root)
  root = vim.fs.normalize(root)
  if cache[root] then
    return cache[root]
  end

  local loaded = store.load(root)
  if loaded then
    loaded.root = root
    cache[root] = loaded
    emit(loaded, 'load')
    return loaded
  end

  ---@type margin.Session
  local session = {
    version = store.VERSION,
    root = root,
    created_at = now_iso(),
    updated_at = now_iso(),
    comments = {},
  }
  cache[root] = session
  return session
end

--- Get the session owning a buffer.
---@param buf integer
---@return margin.Session
function M.for_buf(buf)
  return M.get(M.root_for(buf))
end

--- Flush live positions and write a session to disk.
---@param session margin.Session
---@return boolean ok
---@return string|nil error
function M.persist(session)
  for _, fn in ipairs(sync_hooks) do
    pcall(fn, session)
  end
  session.updated_at = now_iso()
  return store.save(session)
end

--- Extract a filesystem path from a buffer name, honoring file:// URIs.
--- Returns nil for unnamed or non-file (other-scheme) buffers.
---@param buf integer
---@return string|nil
local function buf_fspath(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    return nil
  end
  local scheme = name:match('^(%w[%w+.-]*)://')
  if scheme then
    if scheme == 'file' then
      return vim.uri_to_fname(name)
    end
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

--- Make an absolute path relative to root, or keep it absolute if outside.
---@param abspath string
---@param root string
---@return string
local function relativize(abspath, root)
  local rel = vim.fs.relpath(root, abspath)
  return rel or abspath
end

--- Resolve the stored path and diff side for a comment made in a buffer.
--- Named/file:// buffers use their own path; unnamed buffers inside a diff
--- borrow the counterpart window's path and become old-side comments.
---@param buf integer
---@param win integer|nil window showing the buffer (for counterpart lookup)
---@return string|nil path
---@return "new"|"old"|nil side
---@return string|nil error
function M.resolve_path(buf, win)
  local root = M.root_for(buf)
  local fspath = buf_fspath(buf)
  if fspath then
    return relativize(fspath, root), 'new'
  end

  -- Unnamed / non-file: borrow the counterpart diff window's path.
  local ok, diffmap = pcall(require, 'margin.diffmap')
  if ok and win then
    local cp = diffmap.counterpart(win)
    if cp then
      local cp_path = buf_fspath(cp.buf)
      if cp_path then
        return relativize(cp_path, root), 'old'
      end
    end
  end
  return nil, nil, 'margin: cannot comment on an unnamed buffer without a named diff counterpart'
end

--- Create a comment in the session owning `buf`.
---@param buf integer
---@param lnum integer 1-based start
---@param end_lnum integer 1-based end (>= lnum)
---@param text string comment body
---@param win integer|nil window for counterpart path resolution
---@return margin.Comment|nil comment
---@return string|nil error
function M.add(buf, lnum, end_lnum, text, win)
  if text == nil or text == '' then
    return nil, 'margin: empty comment'
  end
  local path, side, err = M.resolve_path(buf, win)
  if not path then
    return nil, err
  end

  local line0 = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''

  ---@type margin.Comment
  local comment = {
    id = new_id(),
    path = path,
    side = side or 'new',
    lnum = lnum,
    end_lnum = math.max(end_lnum, lnum),
    text = text,
    line_text = line0,
    created_at = now_iso(),
    orphaned = false,
    archived = false,
  }

  local session = M.for_buf(buf)
  table.insert(session.comments, comment)
  M.persist(session)
  emit(session, 'add')
  return comment
end

--- Update a comment's body. Empty text leaves it unchanged.
---@param session margin.Session
---@param comment margin.Comment
---@param text string
function M.edit(session, comment, text)
  if text == nil or text == '' then
    return
  end
  comment.text = text
  M.persist(session)
  emit(session, 'edit')
end

--- Set a comment's archived flag. Archived comments are excluded from export
--- and the default comment list, but keep re-anchoring and render dimmed.
---@param session margin.Session
---@param comment margin.Comment
---@param archived boolean
function M.set_archived(session, comment, archived)
  if comment.archived == archived then
    return
  end
  comment.archived = archived
  M.persist(session)
  emit(session, 'archive')
end

--- Archive the selected comments that are still present and active.
---@param session margin.Session
---@param comments margin.Comment[]
---@return integer archived count newly archived
function M.archive_comments(session, comments)
  local selected = {}
  for _, c in ipairs(comments) do
    selected[c.id] = true
  end

  local n = 0
  for _, c in ipairs(session.comments) do
    if selected[c.id] and not c.archived then
      c.archived = true
      n = n + 1
    end
  end
  if n > 0 then
    M.persist(session)
    emit(session, 'archive')
  end
  return n
end

--- Archive every not-yet-archived comment.
---@param session margin.Session
---@return integer archived count newly archived
function M.archive_active(session)
  return M.archive_comments(session, session.comments)
end

--- Remove a comment from its session.
---@param session margin.Session
---@param comment margin.Comment
function M.delete(session, comment)
  for i, c in ipairs(session.comments) do
    if c.id == comment.id then
      table.remove(session.comments, i)
      break
    end
  end
  M.persist(session)
  emit(session, 'delete')
end

--- Delete every comment in a session and remove its file.
---@param session margin.Session
function M.clear(session)
  session.comments = {}
  M.persist(session)
  emit(session, 'clear')
end

--- All comments in a session for a given stored path, in line order.
---@param session margin.Session
---@param path string
---@return margin.Comment[]
function M.comments_for_path(session, path)
  local out = {}
  for _, c in ipairs(session.comments) do
    if c.path == path then
      out[#out + 1] = c
    end
  end
  table.sort(out, function(a, b)
    return a.lnum < b.lnum
  end)
  return out
end

--- Comments eligible for export / the comment list. Archived comments are
--- excluded unless `include_archived` is set. Order matches storage order.
---@param session margin.Session
---@param include_archived boolean|nil
---@return margin.Comment[]
function M.select_comments(session, include_archived)
  local out = {}
  for _, c in ipairs(session.comments) do
    if include_archived or not c.archived then
      out[#out + 1] = c
    end
  end
  return out
end

--- The stored path a buffer maps to within its session, or nil.
---@param buf integer
---@return string|nil
function M.path_for_buf(buf)
  local path = M.resolve_path(buf)
  return path
end

--- Notify subscribers of an out-of-band change (e.g. re-anchor) and persist.
---@param session margin.Session
---@param event string
function M.touch(session, event)
  M.persist(session)
  emit(session, event or 'change')
end

--- Persist every loaded session (final sync on exit).
function M.persist_all()
  for _, session in pairs(cache) do
    M.persist(session)
  end
end

--- All currently loaded sessions.
---@return margin.Session[]
function M.all()
  local out = {}
  for _, session in pairs(cache) do
    out[#out + 1] = session
  end
  return out
end

--- Drop cached sessions (test isolation). Leaves module-load hooks intact.
function M._reset()
  cache = {}
  id_counter = 0
end

return M
