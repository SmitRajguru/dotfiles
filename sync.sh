#!/usr/bin/env bash
# ~/dotfiles/sync.sh — pull and re-apply symlinks. Strictly local to ~/dotfiles
# (no cross-repo orchestration; run other overlay repos' sync scripts separately if needed).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
git pull --recurse-submodules
git submodule update --init --recursive 2>/dev/null || true

"$REPO/setup.sh"
