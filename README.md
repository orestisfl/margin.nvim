# margin.nvim

Leave local code reviews on top of any Neovim buffer and export them with enough
context to paste into an AI coding agent.

margin.nvim adds decorations to existing buffers. It does not create diff views
or change buffer text.

## Demo

https://github.com/user-attachments/assets/2f52a299-3285-432d-b6d0-e6f614402ec3

## Features

- Add comments to a line or visual range.
- Read comments in virtual-line boxes below the selected lines.
- Keep comments across restarts in one JSON file for each project.
- Open comments in the quickfix list, or move between them with mappings.
- Export comments with diff hunks or code snippets.
- Archive comments after you export them.

## Install

For example, with lazy.nvim:

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
| `:Margin comment` | Add a comment to the current line or range |
| `:Margin edit` | Edit the comment at the cursor |
| `:Margin delete` | Delete the comment at the cursor |
| `:Margin[!] list` | Open the quickfix list. `!` includes archived comments |
| `:Margin[!] export [path]` | Export comments. `!` includes archived comments |
| `:Margin archive` | Archive the comment at the cursor |
| `:Margin unarchive` | Unarchive the comment at the cursor |
| `:Margin archived` | Show or hide archived comments |
| `:Margin inline` | Show or hide inline comment boxes |
| `:Margin clear` | Delete all comments after confirmation |

In the comment window, use `:w` or `<C-s>` to save. If the comment is empty,
use `q` to cancel. If the comment contains text, `q` asks whether to save it.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `inline` | `true` | Show virtual-line comment boxes |
| `show_archived` | `false` | Show archived comments with dim text |
| `max_width` | `80` | Set the maximum width of a comment box |
| `context_lines` | `3` | Set the number of context lines in exports |
| `sign_text` | `┃` | Set the text in the sign column |
| `data_dir` | `nil` | Set the session directory |

The plugin defines these highlight groups: `MarginSign`, `MarginComment`,
`MarginBorder`, `MarginOrphan`, `MarginArchived`.

## Export format

`:Margin export` produces this Markdown:

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

In a diff window, each comment contains the related diff hunk. In other buffers,
each comment contains the selected lines and their context.

Without a path, the export opens in a `margin://export` split. You can edit,
yank, or save the export.

After an export, margin.nvim offers to archive its comments. An export with `!`
does not change their archive state.
