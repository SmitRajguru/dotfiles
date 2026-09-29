#!/usr/bin/env bash
# Mirror Claude Code rule files (*.md) into Cursor rule files (*.mdc).
#
# Usage: rules-to-cursor.sh <rules-dir> <prefix> [cursor-rules-dir]
#
# Each <rules-dir>/<name>.md becomes <cursor-rules-dir>/<prefix>-<name>.mdc, or
# <prefix>-<rest>.mdc when <name> already starts with "<prefix>-".
# Files named claude-*.md are Claude-only and are skipped. A `paths:` list in a
# rule's frontmatter becomes Cursor `globs:` with alwaysApply false; a rule
# without one gets alwaysApply true. Earlier <prefix>-*.mdc files are removed
# first, so a deleted or renamed rule does not linger.
set -euo pipefail

src="$1"
prefix="$2"
dst="${3:-$HOME/.cursor/rules}"

if [ ! -d "$src" ] || [ ! -r "$src" ]; then
  echo "rules-to-cursor: $src is not a readable directory; leaving $dst untouched" >&2
  exit 1
fi

# Work out every output name first, so a collision (foo.md and <prefix>-foo.md)
# is caught before any existing file is removed.
shopt -s nullglob
declare -A seen=()
sources=()
for f in "$src"/*.md; do
  name=$(basename "$f" .md)
  [[ "$name" == claude-* ]] && continue
  out="$dst/$prefix-${name#"$prefix"-}.mdc"
  if [ -n "${seen[$out]:-}" ]; then
    echo "rules-to-cursor: $f and ${seen[$out]} both map to $out" >&2
    exit 1
  fi
  seen[$out]="$f"
  sources+=("$f")
done

mkdir -p "$dst"
rm -f "$dst/$prefix"-*.mdc

for f in "${sources[@]}"; do
  name=$(basename "$f" .md)
  out="$dst/$prefix-${name#"$prefix"-}.mdc"
  # Only list items under a `paths:` key become globs; other frontmatter keys
  # are ignored.
  awk -v src="$f" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"   { in_fm = 0; next }
    in_fm && /^[^[:space:]-][^:]*:/ { in_paths = ($0 ~ /^paths:[[:space:]]*$/); next }
    in_fm && in_paths && /^[[:space:]]*-[[:space:]]/ {
      glob = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", glob)
      gsub(/"/, "", glob)
      globs = globs (globs == "" ? "" : ",") glob
      next
    }
    in_fm { next }
    {
      body[++n] = $0
      if (title == "" && /^# /) title = substr($0, 3)
    }
    END {
      print "---"
      printf "description: %s (generated from %s)\n", title, src
      if (globs != "") { print "globs: " globs; print "alwaysApply: false" }
      else print "alwaysApply: true"
      print "---"
      for (i = 1; i <= n; i++) print body[i]
    }
  ' "$f" > "$out"
  echo "  - $out"
done
