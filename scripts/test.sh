#!/usr/bin/env bash
# Run the mini.test suites headless, exiting nonzero on any failure.
# With no args runs everything; pass a file path to run a single suite.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d deps/mini.nvim ]; then
  echo "deps/mini.nvim missing; cloning..." >&2
  git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim
fi

export MARGIN_TEST_FILE="${1:-}"
nvim --headless --noplugin -u tests/minimal_init.lua -c "luafile tests/run.lua"
