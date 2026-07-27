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

For example with lazy.nvim:

```lua
{
  'orestisfl/margin.nvim',
  lazy = true, -- Set to false to show saved comments when Neovim starts.
  keys = {
    { '<leader>mc', '<Plug>(margin-comment)', mode = { 'n', 'x' } },
    { '<leader>me', '<Plug>(margin-edit)' },
    { '<leader>md', '<Plug>(margin-delete)' },
    { '<leader>ml', '<Plug>(margin-list)' },
    { '<leader>mx', '<Plug>(margin-export)' },
    { '<leader>ma', '<Plug>(margin-archive)' },
    { '<leader>mA', '<Plug>(margin-unarchive)' },
    { '<leader>mt', '<Plug>(margin-archived)' },
    { ']m', '<Plug>(margin-next)', desc = 'Next margin comment' },
    { '[m', '<Plug>(margin-prev)', desc = 'Previous margin comment' },
  },
  opts = { -- The default values:
    inline = true,
    show_archived = false,
    max_width = 80,
    context_lines = 3,
    sign_text = '┃',
    data_dir = nil,
  },
}
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

| Option | Default | Description |
| --- | --- | --- |
| `inline` | `true` | Render virtual-line comment boxes |
| `show_archived` | `false` | Render archived comments dimmed |
| `max_width` | `80` | Maximum comment-box wrap width |
| `context_lines` | `3` | Export context and diff hunk context |
| `sign_text` | `┃` | Sign-column indicator |
| `data_dir` | `nil` | Override `stdpath('data')/margin` |

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

Archived comments do not appear in normal lists or exports. They keep their
positions and move when the related text moves.

`:Margin archived` shows archived comments with dim text. Use `:Margin
unarchive` to make the comment active again.

Add `!` to list or export archived comments. These commands do not change the
archive state.
