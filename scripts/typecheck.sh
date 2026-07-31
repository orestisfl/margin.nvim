#!/usr/bin/env bash
# Run lua-language-server in --check mode over lua/. Exits nonzero on any
# diagnostic. Requires nvim and `lua-language-server` on PATH (or LUA_LS
# pointing at the latter).
set -euo pipefail

cd "$(dirname "$0")/.."

LLS="${LUA_LS:-lua-language-server}"
if ! command -v "$LLS" >/dev/null 2>&1; then
  echo "lua-language-server not found (set LUA_LS or install it)" >&2
  exit 1
fi

# .luarc.json points workspace.library at $VIMRUNTIME, which the language server
# expands from its own environment. Editors inherit it from the nvim that spawns
# them; from a plain shell we have to supply it. Without it the vim API resolves
# to nothing and the check passes while inspecting almost none of the code.
export VIMRUNTIME="${VIMRUNTIME:-$(nvim --headless --clean -c 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c 'quit' 2>/dev/null)}"
if [ ! -d "$VIMRUNTIME/lua" ]; then
  echo "could not locate the Neovim runtime (VIMRUNTIME='$VIMRUNTIME')" >&2
  exit 1
fi

logdir="$(mktemp -d)"
trap 'rm -rf "$logdir"' EXIT

"$LLS" --check lua --checklevel=Warning --configpath="$PWD/.luarc.json" --logpath="$logdir"

# lua-language-server exits 0 even with findings; the presence of check.json
# with content signals problems.
if [ -s "$logdir/check.json" ] && ! grep -q '^\[\]$' "$logdir/check.json"; then
  echo "lua-language-server found problems:" >&2
  cat "$logdir/check.json" >&2
  exit 1
fi
echo "lua-language-server: no problems found"
