#!/usr/bin/env bash
# ~/dotfiles/bootstrap.sh — first-time machine setup. Idempotent; safe to re-run.
# Installs apt deps, builds tmux >= 3.5 from source if needed, installs oh-my-zsh,
# zsh plugins, p10k, tmux-tpm, MesloLGS NF fonts, then runs setup.sh.
#
# Out of scope: secrets (no .ssh/passfile etc.), ssh-copy-id (interactive — print
# a reminder at the end).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
log() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [ "$(uname -s)" != "Linux" ]; then
  echo "bootstrap.sh currently only supports Linux. Aborting." >&2
  exit 1
fi

###############################################################################
log "1. apt packages"
###############################################################################
APT_PKGS=(
  zsh git curl wget hub terminator tmux ssh-askpass
  libncurses5-dev ruby-full rubygems build-essential
  libevent-dev ncurses-dev bison pkg-config
  fzf jq fontconfig
)
MISSING=()
for p in "${APT_PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Installing: ${MISSING[*]}"
  sudo apt-get update
  sudo apt-get install -y "${MISSING[@]}"
else
  echo "All apt packages already present."
fi

###############################################################################
log "2. tmux >= 3.5 (build from source if needed)"
###############################################################################
TMUX_PIN="${TMUX_VERSION:-3.5a}"
need_build=1
if have tmux; then
  ver=$(tmux -V | awk '{print $2}')
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2 | tr -d 'a-z')
  if [ "$major" -gt 3 ] || { [ "$major" = "3" ] && [ "$minor" -ge 5 ]; }; then
    echo "tmux $ver already >= 3.5; skipping source build."
    need_build=0
  else
    echo "tmux $ver < 3.5; will build $TMUX_PIN from source."
  fi
fi
if [ "$need_build" = 1 ]; then
  TMP=$(mktemp -d)
  pushd "$TMP" >/dev/null
  curl -fLO "https://github.com/tmux/tmux/releases/download/${TMUX_PIN}/tmux-${TMUX_PIN}.tar.gz"
  tar xzf "tmux-${TMUX_PIN}.tar.gz"
  cd "tmux-${TMUX_PIN}"
  ./configure
  make -j"$(nproc)"
  sudo make install
  popd >/dev/null
  rm -rf "$TMP"
  echo "Installed tmux $TMUX_PIN."
fi

###############################################################################
log "3. ruby gems"
###############################################################################
if ! gem list -i public_suffix -v 5.1.1 >/dev/null 2>&1; then
  sudo gem install public_suffix -v 5.1.1
fi
if ! have colorls; then
  sudo gem install colorls
fi

###############################################################################
log "4. default shell -> zsh"
###############################################################################
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/bin/zsh" ]; then
  echo "Changing default shell to /bin/zsh (you'll be prompted for password)..."
  chsh -s /bin/zsh
else
  echo "Default shell already /bin/zsh."
fi

###############################################################################
log "5. tpm (tmux plugin manager)"
###############################################################################
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  echo "tpm already cloned."
fi

###############################################################################
log "6. oh-my-zsh"
###############################################################################
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "oh-my-zsh already installed."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

###############################################################################
log "7. zsh plugins (autosuggestions, syntax-highlighting)"
###############################################################################
clone_if_missing() {
  local url="$1" dst="$2"
  if [ ! -d "$dst" ]; then
    git clone "$url" "$dst"
  else
    echo "Already cloned: $dst"
  fi
}
clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

###############################################################################
log "8. powerlevel10k theme"
###############################################################################
clone_if_missing https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k"

###############################################################################
log "9. MesloLGS NF fonts"
###############################################################################
mkdir -p "$HOME/.fonts"
FONT_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONTS=(
  "MesloLGS NF Regular.ttf"
  "MesloLGS NF Bold.ttf"
  "MesloLGS NF Italic.ttf"
  "MesloLGS NF Bold Italic.ttf"
)
need_cache=0
for f in "${FONTS[@]}"; do
  if [ ! -f "$HOME/.fonts/$f" ]; then
    curl -fL -o "$HOME/.fonts/$f" "$FONT_BASE/${f// /%20}"
    need_cache=1
  fi
done
if [ "$need_cache" = 1 ]; then
  fc-cache -vf "$HOME/.fonts" >/dev/null
  echo "Font cache rebuilt."
else
  echo "Fonts already installed."
fi

###############################################################################
log "10. Claude Code CLI"
###############################################################################
if have claude; then
  echo "Claude Code already installed."
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

###############################################################################
log "11. symlinks (setup.sh)"
###############################################################################
"$REPO/setup.sh"

###############################################################################
log "Done"
###############################################################################
cat <<'EOF'

Bootstrap complete.

Next steps:
  - Open a new shell (or `exec zsh`) to pick up XDG zsh config.
  - If you have remote machines you ssh into, run `ssh-copy-id user@host` manually
    (interactive password input — not scripted).
  - Any private/work-specific overlays plug in via $ZDOTDIR/local/*.zsh and
    per-item symlinks under ~/.claude/. Run those overlays' setup scripts
    separately if applicable.

EOF
