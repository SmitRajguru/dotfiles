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
log "2. tmux >= 3.5 (build latest from source if apt too old)"
###############################################################################
# Floor = semantic minimum we need (catppuccin status-format[1] needs 3.5+).
# If apt-installed tmux already meets the floor, use it. Otherwise resolve the
# latest tag from GitHub and build that — no hard-coded pin.
TMUX_FLOOR_MAJOR=3
TMUX_FLOOR_MINOR=5
need_build=1
if have tmux; then
  ver=$(tmux -V | awk '{print $2}')
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2 | tr -d 'a-z')
  if [ "$major" -gt "$TMUX_FLOOR_MAJOR" ] || { [ "$major" = "$TMUX_FLOOR_MAJOR" ] && [ "$minor" -ge "$TMUX_FLOOR_MINOR" ]; }; then
    echo "tmux $ver already >= ${TMUX_FLOOR_MAJOR}.${TMUX_FLOOR_MINOR}; using apt version."
    need_build=0
  else
    echo "tmux $ver < ${TMUX_FLOOR_MAJOR}.${TMUX_FLOOR_MINOR}; will resolve latest from github.com/tmux/tmux."
  fi
fi
if [ "$need_build" = 1 ]; then
  echo "Resolving latest tmux release tag via github.com redirect (30s timeout)..."
  # Follow the /releases/latest redirect; the redirect URL ends with /tag/<tag>.
  # Avoids api.github.com (lower rate limit, sometimes proxy-blocked).
  TMUX_LATEST=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 30 https://github.com/tmux/tmux/releases/latest | sed 's|.*/tag/||' | tr -d '\r\n')
  if [ -z "$TMUX_LATEST" ]; then
    echo "ERROR: could not resolve latest tmux release tag (no redirect)." >&2
    exit 1
  fi
  echo "Latest tmux: $TMUX_LATEST"
  echo "Building tmux $TMUX_LATEST from source..."
  TMP=$(mktemp -d)
  pushd "$TMP" >/dev/null
  curl -fLO "https://github.com/tmux/tmux/releases/download/${TMUX_LATEST}/tmux-${TMUX_LATEST}.tar.gz"
  tar xzf "tmux-${TMUX_LATEST}.tar.gz"
  cd "tmux-${TMUX_LATEST}"
  ./configure
  make -j"$(nproc)"
  sudo make install
  popd >/dev/null
  rm -rf "$TMP"
  echo "Installed tmux $TMUX_LATEST."
fi

###############################################################################
log "3. fzf >= 0.53 (binary from github releases if apt too old)"
###############################################################################
# Floor = 0.53 (first version with `--tmux` popup flag used in FZF_DEFAULT_OPTS).
# If apt fzf meets the floor, keep it. Otherwise install the latest binary
# release into /usr/local/bin (precedes /usr/bin in PATH).
FZF_FLOOR_MAJOR=0
FZF_FLOOR_MINOR=53
need_fzf=1
if have fzf; then
  fzf_path=$(command -v fzf)
  # Run fzf --version with FZF_DEFAULT_OPTS unset, in case the env has flags
  # the installed fzf doesn't understand (the exact bug we're fixing). Also
  # `|| true` to defang any pipefail/errexit propagation from old fzf exiting
  # non-zero before printing version.
  ver=$(FZF_DEFAULT_OPTS= fzf --version 2>/dev/null | awk '{print $1}' || true)
  echo "Detected fzf at $fzf_path, version: ${ver:-<unparsed>}"
  if [ -n "$ver" ]; then
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    if [ "$major" -gt "$FZF_FLOOR_MAJOR" ] || { [ "$major" = "$FZF_FLOOR_MAJOR" ] && [ "$minor" -ge "$FZF_FLOOR_MINOR" ]; }; then
      echo "fzf $ver >= ${FZF_FLOOR_MAJOR}.${FZF_FLOOR_MINOR}; using existing version."
      need_fzf=0
    else
      echo "fzf $ver < ${FZF_FLOOR_MAJOR}.${FZF_FLOOR_MINOR}; will fetch latest from github.com/junegunn/fzf."
    fi
  else
    echo "Could not parse fzf version; will fetch latest."
  fi
else
  echo "fzf not installed; will fetch latest from github.com/junegunn/fzf."
fi
if [ "$need_fzf" = 1 ]; then
  echo "Resolving latest fzf release tag via github.com redirect (30s timeout)..."
  # Follow the /releases/latest redirect; the redirect URL ends with /tag/v<ver>.
  # Avoids api.github.com (lower rate limit; some corporate networks 403 it).
  FZF_LATEST=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 30 https://github.com/junegunn/fzf/releases/latest | sed 's|.*/tag/v||' | tr -d '\r\n')
  if [ -z "$FZF_LATEST" ]; then
    echo "ERROR: could not resolve latest fzf release tag (no redirect)." >&2
    exit 1
  fi
  echo "Latest fzf: $FZF_LATEST"
  arch=$(uname -m)
  case "$arch" in
    x86_64)  FZF_ARCH=amd64 ;;
    aarch64) FZF_ARCH=arm64 ;;
    *) echo "ERROR: unsupported arch for fzf binary: $arch" >&2; exit 1 ;;
  esac
  TARBALL="fzf-${FZF_LATEST}-linux_${FZF_ARCH}.tar.gz"
  TMP=$(mktemp -d)
  pushd "$TMP" >/dev/null
  echo "Downloading $TARBALL..."
  curl -fL --max-time 120 -O "https://github.com/junegunn/fzf/releases/download/v${FZF_LATEST}/${TARBALL}"
  echo "Extracting..."
  tar xzf "$TARBALL"
  echo "Installing to /usr/local/bin/fzf (will prompt for sudo)..."
  sudo install -m 755 fzf /usr/local/bin/fzf
  popd >/dev/null
  rm -rf "$TMP"
  echo "Installed: $(/usr/local/bin/fzf --version)"
fi

###############################################################################
log "4. ruby gems"
###############################################################################
if ! gem list -i public_suffix -v 5.1.1 >/dev/null 2>&1; then
  sudo gem install public_suffix -v 5.1.1
fi
if ! have colorls; then
  sudo gem install colorls
fi

###############################################################################
log "5. default shell -> zsh"
###############################################################################
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/bin/zsh" ]; then
  echo "Changing default shell to /bin/zsh (you'll be prompted for password)..."
  chsh -s /bin/zsh
else
  echo "Default shell already /bin/zsh."
fi

###############################################################################
log "6. tpm (tmux plugin manager)"
###############################################################################
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  echo "tpm already cloned."
fi

###############################################################################
log "7. oh-my-zsh"
###############################################################################
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "oh-my-zsh already installed."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

###############################################################################
log "8. zsh plugins (autosuggestions, syntax-highlighting)"
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
log "9. powerlevel10k theme"
###############################################################################
clone_if_missing https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k"

###############################################################################
log "10. MesloLGS NF fonts"
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
log "11. Claude Code CLI"
###############################################################################
if have claude; then
  echo "Claude Code already installed."
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

###############################################################################
log "12. symlinks (setup.sh)"
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
