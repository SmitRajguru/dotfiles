#!/usr/bin/env bash
# ~/dotfiles/setup.sh — symlink layer (idempotent, safe to re-run after every pull).
# Creates user-level Claude/Cursor symlinks, XDG-bound shell config symlinks, and
# $HOME stragglers. Per-item symlinks (not whole-dir) so external overlay repos
# can layer their own items into the same dirs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CLAUDE_DIR="$HOME/.claude"
CURSOR_DIR="$HOME/.cursor"

mkdir -p \
  "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/scripts" \
  "$CURSOR_DIR/skills" "$CURSOR_DIR/agents" "$CURSOR_DIR/commands" "$CURSOR_DIR/rules" \
  "$XDG_CONFIG_HOME/zsh" "$XDG_CONFIG_HOME/tmux" "$XDG_CONFIG_HOME/p10k" "$XDG_CONFIG_HOME/ccstatusline"

# link <target> <link_path>: replace file/symlink/empty-dir with symlink. Skips non-empty dirs.
link() {
  local target="$1" link_path="$2"
  if [ -d "$link_path" ] && [ ! -L "$link_path" ]; then
    if rmdir "$link_path" 2>/dev/null; then
      :
    else
      echo "  ! $link_path is a non-empty directory, skipping" >&2
      return 0
    fi
  fi
  ln -sfn "$target" "$link_path"
  echo "  - $link_path -> $target"
}

# link_dir_contents <src_dir> <dest_dir>: link each child of src_dir into dest_dir as a symlink.
# Includes dotfiles. Skips . and ..
link_dir_contents() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  shopt -s dotglob nullglob
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    base=$(basename "$entry")
    [ "$base" = "." ] || [ "$base" = ".." ] && continue
    link "$entry" "$dst/$base"
  done
  shopt -u dotglob nullglob
}

echo "[ai] Claude Code config (single-file)"
link "$REPO/ai/CLAUDE.md"     "$CLAUDE_DIR/CLAUDE.md"
link "$REPO/ai/settings.json" "$CLAUDE_DIR/settings.json"

echo "[ai] Claude Code skills/agents/commands/scripts (per-item)"
link_dir_contents "$REPO/ai/skills"   "$CLAUDE_DIR/skills"
link_dir_contents "$REPO/ai/agents"   "$CLAUDE_DIR/agents"
link_dir_contents "$REPO/ai/commands" "$CLAUDE_DIR/commands"
link_dir_contents "$REPO/ai/scripts"  "$CLAUDE_DIR/scripts"

echo "[ai] Cursor (skills/agents/commands)"
link_dir_contents "$REPO/ai/skills"   "$CURSOR_DIR/skills"
link_dir_contents "$REPO/ai/agents"   "$CURSOR_DIR/agents"
link_dir_contents "$REPO/ai/commands" "$CURSOR_DIR/commands"

echo "[ai] Cursor user rules from CLAUDE.md (regenerated)"
cat > "$CURSOR_DIR/rules/personal.mdc" <<'FRONTMATTER'
---
description: Personal instructions and preferences (auto-generated from dotfiles/ai/CLAUDE.md)
alwaysApply: true
---

FRONTMATTER
cat "$REPO/ai/CLAUDE.md" >> "$CURSOR_DIR/rules/personal.mdc"

echo "[ai] ccstatusline"
link "$REPO/ai/ccstatusline/settings.json" "$XDG_CONFIG_HOME/ccstatusline/settings.json"

echo "[config] zsh (XDG)"
link_dir_contents "$REPO/config/zsh" "$XDG_CONFIG_HOME/zsh"

echo "[config] tmux (XDG)"
link "$REPO/config/tmux/tmux.conf" "$XDG_CONFIG_HOME/tmux/tmux.conf"

echo "[config] p10k (XDG)"
link "$REPO/config/p10k/p10k.zsh" "$XDG_CONFIG_HOME/p10k/p10k.zsh"

echo "[home] stragglers"
link "$REPO/home/.zshenv-stub" "$HOME/.zshenv"
link "$REPO/home/.bazelrc"     "$HOME/.bazelrc"

echo "dotfiles setup complete."
