#!/usr/bin/env bash
# ~/dotfiles/bootstrap.sh — first-time machine setup. Idempotent; safe to re-run.
# Installs apt deps, builds tmux >= 3.5 from source if needed, installs oh-my-zsh,
# zsh plugins, p10k, tmux-tpm, MesloLGS NF fonts, then runs setup.sh.
#
# Each step runs in a subshell with `set -e` so a failure inside the step aborts
# only that step, not the whole script. A summary at the end reports ✓ / ✗ per
# step. The script always exits 0 if at least one step ran, so the final summary
# is always reachable; the summary itself surfaces failures.
#
# Out of scope: secrets (no .ssh/passfile etc.), ssh-copy-id (interactive — print
# a reminder at the end).
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [ "$(uname -s)" != "Linux" ]; then
  echo "bootstrap.sh currently only supports Linux. Aborting." >&2
  exit 1
fi

###############################################################################
# Step runner — captures per-step status, prints summary on EXIT.
###############################################################################
declare -a STEP_NAMES=()
declare -a STEP_STATUSES=()
declare -a STEP_MESSAGES=()

run_step() {
  local name=$1 fn=$2
  log "$name"
  STEP_NAMES+=("$name")
  local rc=0
  # Run the step in a fresh `bash -e` subprocess. Subshells `( set -e; fn ) ||`
  # silently disable errexit (POSIX rule: compound commands whose status is
  # tested suppress -e). A separate process avoids that — any non-zero command
  # inside the step body aborts the step, but the parent script keeps going.
  REPO="$REPO" ZSH_CUSTOM="$ZSH_CUSTOM" \
    bash -euo pipefail -c "$(declare -f log have clone_if_missing "$fn"); $fn" \
    || rc=$?
  if [ "$rc" -eq 0 ]; then
    STEP_STATUSES+=("ok")
    STEP_MESSAGES+=("")
  else
    STEP_STATUSES+=("fail")
    STEP_MESSAGES+=("exit $rc")
    printf '\n!! step failed (exit %d) — continuing\n' "$rc" >&2
  fi
}

print_summary() {
  local rc=$?
  echo
  echo "==================== bootstrap summary ===================="
  local i sym color reset extra
  reset=$'\033[0m'
  local any_fail=0
  for ((i=0; i<${#STEP_NAMES[@]}; i++)); do
    case "${STEP_STATUSES[i]}" in
      ok)   sym='✓'; color=$'\033[32m' ;;
      fail) sym='✗'; color=$'\033[31m'; any_fail=1 ;;
      *)    sym='?'; color=$'\033[33m' ;;
    esac
    extra=""
    [ -n "${STEP_MESSAGES[i]}" ] && extra=" (${STEP_MESSAGES[i]})"
    printf "  %s%s%s  %s%s\n" "$color" "$sym" "$reset" "${STEP_NAMES[i]}" "$extra"
  done
  echo "==========================================================="
  if [ "$any_fail" = 1 ]; then
    printf "%sOne or more steps failed. Review output above.%s\n" $'\033[31m' "$reset"
  fi
  return "$rc"
}
trap print_summary EXIT

###############################################################################
step_apt() {
  local APT_PKGS=(
    zsh git curl wget hub terminator tmux ssh-askpass
    libncurses5-dev build-essential
    libevent-dev ncurses-dev bison pkg-config
    fzf jq fontconfig
    software-properties-common
  )
  local MISSING=()
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
}

###############################################################################
step_tmux() {
  # Floor = semantic minimum we need (catppuccin status-format[1] needs 3.5+).
  # If apt-installed tmux already meets the floor, use it. Otherwise resolve the
  # latest tag from GitHub and build that — no hard-coded pin.
  local TMUX_FLOOR_MAJOR=3 TMUX_FLOOR_MINOR=5
  local need_build=1 ver major minor
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
    local TMUX_LATEST
    TMUX_LATEST=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 30 https://github.com/tmux/tmux/releases/latest | sed 's|.*/tag/||' | tr -d '\r\n')
    if [ -z "$TMUX_LATEST" ]; then
      echo "ERROR: could not resolve latest tmux release tag (no redirect)." >&2
      return 1
    fi
    echo "Latest tmux: $TMUX_LATEST"
    echo "Building tmux $TMUX_LATEST from source..."
    local TMP
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
}

###############################################################################
step_fzf() {
  # Floor = 0.53 (first version with `--tmux` popup flag used in FZF_DEFAULT_OPTS).
  # If apt fzf meets the floor, keep it. Otherwise install the latest binary
  # release into /usr/local/bin (precedes /usr/bin in PATH).
  local FZF_FLOOR_MAJOR=0 FZF_FLOOR_MINOR=53
  local need_fzf=1 fzf_path ver major minor
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
    local FZF_LATEST
    FZF_LATEST=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 30 https://github.com/junegunn/fzf/releases/latest | sed 's|.*/tag/v||' | tr -d '\r\n')
    if [ -z "$FZF_LATEST" ]; then
      echo "ERROR: could not resolve latest fzf release tag (no redirect)." >&2
      return 1
    fi
    echo "Latest fzf: $FZF_LATEST"
    local arch FZF_ARCH
    arch=$(uname -m)
    case "$arch" in
      x86_64)  FZF_ARCH=amd64 ;;
      aarch64) FZF_ARCH=arm64 ;;
      *) echo "ERROR: unsupported arch for fzf binary: $arch" >&2; return 1 ;;
    esac
    local TARBALL="fzf-${FZF_LATEST}-linux_${FZF_ARCH}.tar.gz"
    local TMP
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
}

###############################################################################
step_default_shell() {
  # Moved ahead of ruby so a gem failure can't block shell switch.
  if [ "$(getent passwd "$USER" | cut -d: -f7)" = "/bin/zsh" ]; then
    echo "Default shell already /bin/zsh."
    return 0
  fi
  echo "Changing default shell to /bin/zsh (you'll be prompted for password)..."
  chsh -s /bin/zsh
}

###############################################################################
step_ruby() {
  # Floor = 3.0 (current `manpages` gem — a transitive dep of colorls — requires
  # ruby >= 3.0). Ubuntu 20.04 focal ships ruby 2.7 in apt and has no working
  # 3.x via snap (snap ruby is built against glibc 2.34+, focal has 2.31) or
  # brightbox PPA (focal only goes to 2.7). rbenv builds ruby from source
  # against the host glibc and installs into ~/.rbenv (user-scope, no sudo).
  local RUBY_FLOOR_MAJOR=3 RUBY_FLOOR_MINOR=0
  local RUBY_VERSION_TARGET="3.4.9"
  local RBENV_ROOT="$HOME/.rbenv"

  # Clean up any prior broken snap-ruby attempt (left over from a previous
  # bootstrap iteration). Snap ruby on focal silently links against newer
  # glibc — `ruby --version` returns non-zero. Detect and remove.
  if [ -x /snap/bin/ruby ] && ! /snap/bin/ruby --version >/dev/null 2>&1; then
    echo "Removing broken snap ruby (incompatible glibc on focal)..."
    sudo snap remove ruby 2>/dev/null || true
  fi
  local stale_bin
  for stale_bin in ruby gem bundle erb irb rake rdoc ri; do
    if [ -L "/usr/local/bin/$stale_bin" ] \
       && [ "$(readlink "/usr/local/bin/$stale_bin")" = "/snap/bin/$stale_bin" ]; then
      sudo rm -f "/usr/local/bin/$stale_bin"
    fi
  done

  # Skip if a working ruby >= floor is already on PATH (system, rbenv, or
  # otherwise). `ruby --version` standalone — errexit catches a broken binary.
  if have ruby; then
    local ver major minor
    ver=$(ruby -e 'puts RUBY_VERSION' 2>/dev/null || true)
    if [ -n "$ver" ]; then
      major=$(echo "$ver" | cut -d. -f1)
      minor=$(echo "$ver" | cut -d. -f2)
      if [ "$major" -gt "$RUBY_FLOOR_MAJOR" ] || { [ "$major" = "$RUBY_FLOOR_MAJOR" ] && [ "$minor" -ge "$RUBY_FLOOR_MINOR" ]; }; then
        echo "ruby $ver >= ${RUBY_FLOOR_MAJOR}.${RUBY_FLOOR_MINOR}; nothing to do."
        return 0
      fi
      echo "ruby $ver < ${RUBY_FLOOR_MAJOR}.${RUBY_FLOOR_MINOR}; installing rbenv + ruby ${RUBY_VERSION_TARGET}."
    fi
  else
    echo "ruby not present; installing rbenv + ruby ${RUBY_VERSION_TARGET}."
  fi

  # rbenv + ruby-build clone (idempotent).
  if [ ! -d "$RBENV_ROOT" ]; then
    git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
  else
    echo "rbenv already cloned at $RBENV_ROOT"
  fi
  if [ ! -d "$RBENV_ROOT/plugins/ruby-build" ]; then
    git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"
  else
    echo "ruby-build plugin already cloned"
  fi

  # ruby-build needs these to compile ruby 3.x. apt-installed list — request
  # explicitly here (not in step 1) so step 1's `MISSING` check doesn't conflate.
  local BUILD_DEPS=(
    autoconf bison patch rustc
    libssl-dev libyaml-dev libreadline-dev zlib1g-dev libgmp-dev
    libncurses5-dev libffi-dev libgdbm-dev libdb-dev uuid-dev
  )
  local missing=()
  for p in "${BUILD_DEPS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing ruby-build deps: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
  fi

  export PATH="$RBENV_ROOT/bin:$PATH"
  if rbenv versions --bare 2>/dev/null | grep -qx "$RUBY_VERSION_TARGET"; then
    echo "ruby ${RUBY_VERSION_TARGET} already installed via rbenv."
  else
    echo "Building ruby ${RUBY_VERSION_TARGET} from source (5-10 min)..."
    rbenv install --skip-existing "$RUBY_VERSION_TARGET"
  fi
  rbenv global "$RUBY_VERSION_TARGET"
  rbenv rehash

  # Standalone verify — bash errexit triggers on non-zero, so a broken binary
  # aborts the step (last run's bug was that `echo "Installed: $(...)"` masked
  # the command-sub failure).
  "$RBENV_ROOT/shims/ruby" --version
  echo "Installed: ruby ${RUBY_VERSION_TARGET} (rbenv shim at $RBENV_ROOT/shims/ruby)"
}

###############################################################################
step_ruby_gems() {
  # rbenv shims aren't on the bash subprocess's inherited PATH. Re-export here
  # so `gem` resolves to the rbenv version installed in step 5. Gems land under
  # ~/.rbenv/versions/<ver>/lib/ruby/gems/ — no sudo, no --user-install.
  if [ -d "$HOME/.rbenv" ]; then
    export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
  fi
  if ! have gem; then
    echo "ERROR: no gem on PATH (rbenv install in step 5 must have failed)." >&2
    return 1
  fi
  if ! gem list -i public_suffix -v 5.1.1 >/dev/null 2>&1; then
    gem install public_suffix -v 5.1.1
  else
    echo "public_suffix 5.1.1 already installed."
  fi
  if ! gem list -i colorls >/dev/null 2>&1; then
    gem install colorls
  else
    echo "colorls already installed."
  fi
  # rbenv rehash so `colorls` becomes a shim resolvable on PATH.
  if have rbenv; then rbenv rehash; fi
}

###############################################################################
step_tpm() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  else
    echo "tpm already cloned."
  fi
}

###############################################################################
step_oh_my_zsh() {
  # Key the check on the file .zshrc actually sources, not the directory:
  # the plugin/theme clones (later steps) create ~/.oh-my-zsh/custom/ via git's
  # parent-dir creation, so the dir existing does not mean OMZ is installed.
  local omz="$HOME/.oh-my-zsh"
  if [ -f "$omz/oh-my-zsh.sh" ]; then
    echo "oh-my-zsh already installed."
    return 0
  fi
  if [ -d "$omz" ]; then
    # Safe to delete: a half-installed dir only ever holds the plugin/theme
    # clones from later steps, which re-clone into the fresh custom/.
    echo "Incomplete oh-my-zsh at $omz (no oh-my-zsh.sh) — removing"
    rm -rf "$omz"
  fi
  # Plain clone instead of the upstream installer: the installer's other jobs
  # (.zshrc template, chsh) are handled by setup.sh symlinks and step 4, and
  # `sh -c "$(curl ...)"` silently succeeds as a no-op when curl fails.
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$omz"
  [ -f "$omz/oh-my-zsh.sh" ]
}

###############################################################################
clone_if_missing() {
  local url="$1" dst="$2"
  if [ ! -d "$dst" ]; then
    git clone "$url" "$dst"
  else
    echo "Already cloned: $dst"
  fi
}

step_zsh_plugins() {
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
}

step_p10k() {
  clone_if_missing https://github.com/romkatv/powerlevel10k.git \
    "$ZSH_CUSTOM/themes/powerlevel10k"
}

###############################################################################
step_fonts() {
  mkdir -p "$HOME/.fonts"
  local FONT_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
  local FONTS=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
  )
  local need_cache=0 f
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
}

###############################################################################
step_claude_cli() {
  if have claude; then
    echo "Claude Code already installed."
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

###############################################################################
step_rclone() {
  # Userspace install (no sudo) of the rclone static binary into ~/.local/bin.
  # Floor = 1.74. Generic binary only — remote config / mounts live elsewhere.
  local RCLONE_FLOOR="1.74"
  local RCLONE_BIN="$HOME/.local/bin/rclone"
  local need=1 ver
  if [ -x "$RCLONE_BIN" ] || have rclone; then
    ver=$({ [ -x "$RCLONE_BIN" ] && "$RCLONE_BIN" version || rclone version; } 2>/dev/null | awk 'NR==1{sub(/^v/,"",$2); print $2}')
    if [ -n "$ver" ] && [ "$(printf '%s\n%s\n' "$RCLONE_FLOOR" "$ver" | sort -V | head -1)" = "$RCLONE_FLOOR" ]; then
      echo "rclone $ver >= $RCLONE_FLOOR; using existing binary."
      need=0
    else
      echo "rclone ${ver:-<unparsed>} < $RCLONE_FLOOR; will fetch latest static binary."
    fi
  else
    echo "rclone not installed; will fetch latest static binary into ~/.local/bin."
  fi
  if [ "$need" = 1 ]; then
    local arch RCLONE_ARCH
    arch=$(uname -m)
    case "$arch" in
      x86_64)  RCLONE_ARCH=amd64 ;;
      aarch64) RCLONE_ARCH=arm64 ;;
      *) echo "ERROR: unsupported arch for rclone binary: $arch" >&2; return 1 ;;
    esac
    mkdir -p "$HOME/.local/bin"
    local TMP
    TMP=$(mktemp -d)
    pushd "$TMP" >/dev/null
    local ZIP="rclone-current-linux-${RCLONE_ARCH}.zip"
    echo "Downloading $ZIP from downloads.rclone.org..."
    curl -fL --max-time 120 -O "https://downloads.rclone.org/$ZIP"
    unzip -q "$ZIP"
    install -m 0755 rclone-*-linux-"${RCLONE_ARCH}"/rclone "$RCLONE_BIN"
    popd >/dev/null
    rm -rf "$TMP"
    echo "Installed: $("$RCLONE_BIN" version 2>/dev/null | awk 'NR==1{print $2}') -> $RCLONE_BIN"
  fi
}

###############################################################################
step_symlinks() {
  "$REPO/setup.sh"
}

###############################################################################
# Run.
###############################################################################
run_step "1. apt packages"                          step_apt
run_step "2. tmux >= 3.5 (build from source if too old)" step_tmux
run_step "3. fzf >= 0.53 (binary from github if too old)" step_fzf
run_step "4. default shell -> zsh"                  step_default_shell
run_step "5. ruby >= 3.0 (brightbox PPA if too old)" step_ruby
run_step "6. ruby gems (public_suffix, colorls)"    step_ruby_gems
run_step "7. tpm (tmux plugin manager)"             step_tpm
run_step "8. oh-my-zsh"                             step_oh_my_zsh
run_step "9. zsh plugins (autosuggestions, syntax-highlighting)" step_zsh_plugins
run_step "10. powerlevel10k theme"                  step_p10k
run_step "11. MesloLGS NF fonts"                    step_fonts
run_step "12. Claude Code CLI"                      step_claude_cli
run_step "13. rclone >= 1.74 (userspace binary)"    step_rclone
run_step "14. symlinks (setup.sh)"                  step_symlinks

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
