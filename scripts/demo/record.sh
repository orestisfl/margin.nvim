#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEMO_GIT="$ROOT/scripts/demo/fixtures/.git"

rm -rf "$ROOT/scripts/demo/.data"
mkdir -p "$ROOT/assets"
mkdir -p "$DEMO_GIT"
trap 'rmdir "$DEMO_GIT"' EXIT

cd "$ROOT"
vhs scripts/demo/demo.tape
