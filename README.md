# margin.nvim

Leave local code reviews on top of any Neovim buffer and export them with enough
context to paste into an AI coding agent.

margin.nvim is **attach-only**: it never opens diffs, windows, or scratch
buffers. You set up diffs however you like (`nvim -d a b`, `:diffthis`, a git
plugin's diff-split) and margin renders on top. It never modifies buffer text,
only decorations.

## Features

- **Comment** on a line or visual range in any buffer, composed in a floating
  markdown scratch buffer.
- **Inline rendering** as virtual-line boxes under the commented line.
- **Persistence** across restarts, keyed by project root, stored as JSON.
- **Navigation** via the quickfix list plus next/prev-comment motions.
- **Export** to clipboard or file as a fixed markdown format with per-comment
  diff hunks or code snippets.

## Install

lazy.nvim:

```lua
{ 'orestisfl/margin.nvim', opts = {} }
```

`setup()` is optional; every command works with defaults.

## Suggested keymaps

No default keymaps are created. Copy this block:

```lua
local map = vim.keymap.set
map({ 'n', 'x' }, '<leader>mc', '<Plug>(margin-comment)')
map('n', '<leader>me', '<Plug>(margin-edit)')
map('n', '<leader>md', '<Plug>(margin-delete)')
map('n', '<leader>ml', '<Plug>(margin-list)')
map('n', '<leader>mx', '<Plug>(margin-export)')
map('n', ']m', '<Plug>(margin-next)')
map('n', '[m', '<Plug>(margin-prev)')
```

## Commands

| Command | Description |
| --- | --- |
| `:Margin comment` | Comment on the current line or visual range |
| `:Margin edit` | Edit the comment under the cursor |
| `:Margin delete` | Delete the comment under the cursor |
| `:Margin list` | Open the quickfix list with all comments |
| `:Margin export [path]` | Export markdown to clipboard, or to a file |
| `:Margin inline` | Toggle inline boxes (signs stay) |
| `:Margin clear` | Delete all comments (after confirmation) |

In the composer: `:w` or `<C-s>` saves, `q` (normal mode) or closing the window
aborts.

## Configuration

```lua
require('margin').setup({
  inline = true,        -- render virtual-line comment boxes
  max_width = 80,       -- comment box wrap width
  context_lines = 3,    -- export context / diff hunk ctxlen
  sign_text = '┃',      -- sign-column indicator
  data_dir = nil,       -- override stdpath('data')/margin
})
```

Highlight groups (override freely): `MarginSign`, `MarginComment`,
`MarginBorder`, `MarginOrphan`.

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

## Manual QA checklist

1. `nvim -d a.txt b.txt`; comment on a line on each side; both panes stay
   aligned.
2. Comment on a visual range; header shows `path:lnum-end`.
3. `:Margin list` opens the quickfix; entries jump to the right lines.
4. `]m` / `[m` cycle comments and wrap.
5. Quit and reopen the same diff; comments are restored at the right lines.
6. Edit a commented file outside Neovim (move the line); reopen; the comment
   relocates or is marked `(stale)`.
7. `:Margin export` lands valid markdown on the clipboard.
8. Comment in a plain (non-diff) buffer; export uses a code snippet.
9. `:Margin toggle` hides boxes but keeps signs.
10. `:checkhealth margin` reports version, clipboard, data dir, session count.

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
