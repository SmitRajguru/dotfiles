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
  "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/rules" \
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

# prune_stale_links <dest_dir>: remove symlinks in dest_dir that point into this
# repo at something that no longer exists (a skill, rule or command that was
# deleted or renamed here). Links owned by overlay repos are left alone.
prune_stale_links() {
  local dst="$1" entry
  [ -d "$dst" ] || return 0
  shopt -s dotglob nullglob
  for entry in "$dst"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ] && [[ "$(readlink "$entry")" == "$REPO"/* ]]; then
      rm "$entry"
      echo "  - removed stale $entry"
    fi
  done
  shopt -u dotglob nullglob
}

echo "[ai] Claude Code config"
link "$REPO/ai/CLAUDE.md"     "$CLAUDE_DIR/CLAUDE.md"
link "$REPO/ai/settings.json" "$CLAUDE_DIR/settings.json"

echo "[ai] Claude Code skills/agents/commands/scripts/rules (per-item)"
for kind in skills agents commands scripts rules; do
  prune_stale_links "$CLAUDE_DIR/$kind"
  link_dir_contents "$REPO/ai/$kind" "$CLAUDE_DIR/$kind"
done

echo "[ai] Cursor (skills/agents/commands)"
for kind in skills agents commands; do
  prune_stale_links "$CURSOR_DIR/$kind"
  link_dir_contents "$REPO/ai/$kind" "$CURSOR_DIR/$kind"
done

echo "[ai] Cursor rules from ai/rules (regenerated; claude-*.md skipped)"
"$REPO/ai/scripts/rules-to-cursor.sh" "$REPO/ai/rules" dotfiles "$CURSOR_DIR/rules"

echo "[ai] Cursor user rules from CLAUDE.md (regenerated)"
# Written to a temp file and moved into place, so an existing symlink at the
# destination is replaced rather than followed. personal.mdc is the name used
# before the dotfiles- prefix; remove it if an older setup left it behind.
personal_tmp=$(mktemp "$CURSOR_DIR/rules/.dotfiles-personal.XXXXXX")
{
  printf '%s\n' '---' \
    'description: Personal instructions and preferences (generated from dotfiles/ai/CLAUDE.md)' \
    'alwaysApply: true' '---' ''
  cat "$REPO/ai/CLAUDE.md"
} > "$personal_tmp"
mv -f "$personal_tmp" "$CURSOR_DIR/rules/dotfiles-personal.mdc"
rm -f "$CURSOR_DIR/rules/personal.mdc"

echo "[ai] ccstatusline"
# An overlay repo may replace this symlink with a real file so it can merge in
# widgets this repo doesn't ship. Re-symlinking would silently drop them, so
# only claim the path when the live file carries no widget ids beyond ours.
ccsl_widget_ids() { jq -r '[.lines[]?[]?.id // empty] | unique | .[]' "$1" 2>/dev/null; }
CCSL_SRC="$REPO/ai/ccstatusline/settings.json"
CCSL_DST="$XDG_CONFIG_HOME/ccstatusline/settings.json"
if [ -f "$CCSL_DST" ] && [ ! -L "$CCSL_DST" ] &&
   [ -n "$(comm -13 <(ccsl_widget_ids "$CCSL_SRC") <(ccsl_widget_ids "$CCSL_DST"))" ]; then
  echo "  - $CCSL_DST left as-is (real file carrying widgets this repo doesn't own)"
else
  link "$CCSL_SRC" "$CCSL_DST"
fi

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
