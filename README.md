# margin.nvim

Leave local code reviews on top of any Neovim buffer and export them with enough
context to paste into an AI coding agent.

margin.nvim is attach-only and doesn't open diffs. You set up diffs however you
like and margin renders on top.

## Features

- **Comment** on a line or visual range in any buffer, composed in a floating
  markdown scratch buffer.
- **Inline rendering** as virtual-line boxes under the commented line.
- **Persistence** across restarts, keyed by project root, stored as JSON.
- **Navigation** via the quickfix list plus next/prev-comment motions.
- **Export** to a scratch buffer or file as a fixed markdown format with
  per-comment diff hunks or code snippets.
- **Archive** old comments.

## Install

lazy.nvim:

```lua
{ 'orestisfl/margin.nvim', opts = {} }
```

`setup()` is optional; every command works with defaults.

### Lazy-loading

margin can load on demand. Any `<Plug>` mapping or `:Margin` command fully
activates it, including a one-time pass that restores comments in buffers that
were already open. Load on the keymaps:

```lua
{
  'orestisfl/margin.nvim',
  keys = {
    { '<leader>mc', '<Plug>(margin-comment)', mode = { 'n', 'x' } },
    { ']m', '<Plug>(margin-next)' },
    { '[m', '<Plug>(margin-prev)' },
  },
  cmd = 'Margin',
  opts = {},
}
```

To restore comments on reopened diffs *without* first pressing a key, load on
buffer-read instead:

```lua
{ 'orestisfl/margin.nvim', event = { 'BufReadPost', 'BufWinEnter' }, opts = {} }
```

## Suggested keymaps

No default keymaps are created. Copy this block:

```lua
local map = vim.keymap.set
map({ 'n', 'x' }, '<leader>mc', '<Plug>(margin-comment)')
map('n', '<leader>me', '<Plug>(margin-edit)')
map('n', '<leader>md', '<Plug>(margin-delete)')
map('n', '<leader>ml', '<Plug>(margin-list)')
map('n', '<leader>mx', '<Plug>(margin-export)')
map('n', '<leader>ma', '<Plug>(margin-archive)')
map('n', '<leader>mA', '<Plug>(margin-unarchive)')
map('n', '<leader>mt', '<Plug>(margin-archived)')
map('n', ']m', '<Plug>(margin-next)')
map('n', '[m', '<Plug>(margin-prev)')
```

## Commands

| Command | Description |
| --- | --- |
| `:Margin comment` | Comment on the current line or visual range |
| `:Margin edit` | Edit the comment under the cursor |
| `:Margin delete` | Delete the comment under the cursor |
| `:Margin list[!]` | Open the quickfix list; `!` includes archived comments |
| `:Margin export[!] [path]` | Export markdown to a scratch split, or to a file (which offers to archive what it wrote); `!` includes archived and archives nothing |
| `:Margin archive` | Archive the comment under the cursor |
| `:Margin unarchive` | Unarchive the comment under the cursor |
| `:Margin archived` | Toggle visibility of archived comments (dimmed) |
| `:Margin inline` | Toggle inline boxes (signs stay) |
| `:Margin clear` | Delete all comments (after confirmation) |

In the composer: `:w` or `<C-s>` saves, `q` (normal mode) or closing the window
aborts.

## Configuration

```lua
require('margin').setup({
  inline = true,         -- render virtual-line comment boxes
  show_archived = false, -- render archived comments (dimmed)
  max_width = 80,        -- comment box wrap width
  context_lines = 3,     -- export context / diff hunk ctxlen
  sign_text = '┃',       -- sign-column indicator
  data_dir = nil,        -- override stdpath('data')/margin
})
```

Highlight groups (override freely): `MarginSign`, `MarginComment`,
`MarginBorder`, `MarginOrphan`, `MarginArchived`.

## Export format

`:Margin export` produces markdown like:

````markdown
I reviewed the changes. Please address the following comments.

## internal/auth/client.go:42

This retry loop never backs off.

```diff
@@ -1,5 +1,5 @@
 func connect(ctx context.Context, cfg Config) error {
-    for i := 0; i < 3; i++ {
+    for {
         err := tryConnect(ctx, cfg)
```
````

In a live diff window the context is the relevant unified-diff hunk; elsewhere
it is the commented lines plus context, fenced with the file's language.

Without a path the markdown opens in a `margin://export` scratch split, ready
to edit, yank, or `:w file`. Re-exporting replaces its contents.

## Archiving

Archiving stops you from handing off the same comment twice. Writing an export
to a file (`:Margin export review.md`) asks whether to archive the comments it
wrote; answer yes and the next file export contains only comments added since,
or decline (Esc / No) to keep them active. The scratch-split preview (no path)
never archives.

Archived comments are hidden by default and drop out of `:Margin export` and
`:Margin list`, but keep their position and still re-anchor. `:Margin archived`
toggles them visible, rendered dimmed with an `(archived)` tag; that's how you
put the cursor on one to `:Margin unarchive` it. Visibility is independent of
export: to include archived comments in output, add `!` (`:Margin list!`,
`:Margin export!`), which archives nothing further.

Archive or unarchive the comment under the cursor with `:Margin archive` /
`:Margin unarchive`.

## Manual QA checklist

1. `nvim -d a.txt b.txt`; comment on a line on each side; both panes stay
   aligned.
2. Comment on a visual range; header shows `path:lnum-end`.
3. `:Margin list` opens the quickfix; entries jump to the right lines.
4. `]m` / `[m` cycle comments and wrap.
5. Quit and reopen the same diff; comments are restored at the right lines.
6. Edit a commented file outside Neovim (move the line); reopen; the comment
   relocates or is marked `(stale)`.
7. `:Margin export` opens valid markdown in a scratch split; re-export reuses
   it.
8. Comment in a plain (non-diff) buffer; export uses a code snippet.
9. `:Margin toggle` hides boxes but keeps signs.
10. `:Margin export review.md`; answer yes at the prompt; the exported comments
    vanish. `:Margin archived` shows them dimmed with an `(archived)` tag; a
    second `:Margin export review.md` reports no comments. Answering no at the
    prompt keeps them active.
11. `:checkhealth margin` reports version, data dir, session count.

## Development

Tooling: [StyLua], [Selene], [lua-language-server], and [mini.test].

```sh
make fmt         # format
make lint        # selene
make typecheck   # lua-language-server --check
make test        # mini.test suites
make check       # all of the above (what pre-commit runs)
```

Install the git hooks with [pre-commit]:

```sh
pre-commit install
```

[StyLua]: https://github.com/JohnnyMorganz/StyLua
[Selene]: https://github.com/Kampfkarren/selene
[lua-language-server]: https://github.com/LuaLS/lua-language-server
[mini.test]: https://github.com/echasnovski/mini.nvim
[pre-commit]: https://pre-commit.com
