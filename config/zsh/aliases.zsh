
# general
alias git=hub
alias p10k-wizard='p10k configure'
export HISTTIMEFORMAT="%d/%m/%y %T "
export PATH=/home/srajguru/.local/bin:$PATH

if [ -n "$BASH_VERSION" ]; then
	alias srcset='source ~/.bashrc'
	alias runset='. ~/.bash_aliases'
elif [ -n "$ZSH_VERSION" ]; then
	alias srcset='source ${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}/.zshrc'
	alias runset='. ${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}/aliases.zsh'
  setopt HIST_IGNORE_SPACE
  setopt TRAPS_ASYNC  # deliver signals during ZLE so TRAPUSR1 fires at the prompt

  # Signal handler for non-disruptive p10k prompt refresh.
  # With TRAPS_ASYNC, this fires immediately during ZLE (not deferred to next Enter).
  # Must re-run precmd hooks so p10k re-queries gitstatus (zle .reset-prompt alone
  # only re-renders from cached state). Preserves typed-but-unexecuted input.
  TRAPUSR1() {
    local f
    for f in $precmd_functions; do
      (( $+functions[$f] )) && "$f" 2>/dev/null
    done
    zle .reset-prompt 2>/dev/null
    return 0
  }

  # Clear pane label when shell returns to prompt (prevents stale labels after command finishes)
  _clear_pane_label() { [ -n "$TMUX" ] && tmux set-option -pu @pane_label 2>/dev/null; }
  precmd_functions=(${precmd_functions:#_clear_pane_label} _clear_pane_label)

  # Deferred command: busy panes auto-run the command on next prompt
  # File format: version|command (latest command wins)
  # Panes already served have @deferred_version set to the current version
  _check_deferred_cmd() {
    [[ -n "$TMUX" ]] || return 0
    local pending="/tmp/tmux-deferred-cmd"
    [[ -f "$pending" ]] || return 0
    local line ver cmd
    line=$(< "$pending") 2>/dev/null || return 0
    ver="${line%%|*}"
    cmd="${line#*|}"
    # Skip if this pane was already served (idle panes get the command immediately)
    local pane_ver
    pane_ver=$(tmux show-options -pv @deferred_version 2>/dev/null)
    # New pane — mark as current version without executing
    if [[ -z "$pane_ver" ]]; then
      tmux set-option -p @deferred_version "$ver" 2>/dev/null
      return 0
    fi
    [[ "$pane_ver" == "$ver" ]] && return 0
    # Mark as served and execute
    tmux set-option -p @deferred_version "$ver" 2>/dev/null
    echo "\n\n\n**** deferred send-all command ****"
    echo "> $cmd\n"
    eval "$cmd" 2>/dev/null
  }
  precmd_functions=(${precmd_functions:#_check_deferred_cmd} _check_deferred_cmd)
else
  echo "Unknown shell type"
fi

# fzf in tmux popup
export FZF_DEFAULT_OPTS='--tmux center,50%,40%'

# Catppuccin syntax highlighting flavor switchers
alias catppuccin-latte='source ${ZDOTDIR:-$HOME}/catppuccin_latte-zsh-syntax-highlighting.zsh'
alias catppuccin-frappe='source ${ZDOTDIR:-$HOME}/catppuccin_frappe-zsh-syntax-highlighting.zsh'
alias catppuccin-macchiato='source ${ZDOTDIR:-$HOME}/catppuccin_macchiato-zsh-syntax-highlighting.zsh'
alias catppuccin-mocha='source ${ZDOTDIR:-$HOME}/catppuccin_mocha-zsh-syntax-highlighting.zsh'

if [ -x "$(command -v colorls)" ]; then
	alias ls="colorls"
	alias la="colorls -al"
	alias lc='colorls -lA --sd'
	#subl $(dirname $(gem which colorls))/yaml
	source $(dirname $(gem which colorls))/tab_complete.sh
fi

cls(){
	# clear; # <--- uncomment to clear shell on alias commands
	echo "Retaining past shell activity"
}


# Set tmux pane label (user option @pane_label, preferred over command name in pane border)
_pane_title() {
    [ -n "$TMUX" ] && {
        tmux select-pane -T "$1"
        tmux set-option -p @pane_label "$1"
    }
}

# Check if a process has a SIGUSR1 handler (bit 9 in /proc/PID/status SigCgt).
# Without a handler, USR1's default action is to TERMINATE the process.
_has_usr1_handler() {
    local sigcgt
    sigcgt=$(awk '/^SigCgt:/{print $2}' "/proc/$1/status" 2>/dev/null) || return 1
    (( 16#$sigcgt & 0x200 ))
}

# Send SIGUSR1 to zsh panes under a specific worktree path to refresh their prompts
_refresh_panes_for_path() {
    local target="$1"
    [[ -z "$target" ]] && return 1
    tmux info >/dev/null 2>&1 || return 0
    tmux list-panes -a -F '#{pane_pid} #{pane_current_command} #{pane_current_path}' \
    | while read -r pid cmd ppath; do
        [[ "$cmd" != "zsh" ]] && continue
        [[ "$ppath" != "$target" && "$ppath" != "$target/"* ]] && continue
        _has_usr1_handler "$pid" || continue
        kill -USR1 "$pid" 2>/dev/null
    done
}

# git
# alias git-agent='eval "$(ssh-agent -s)"'
# alias git-add='ssh-add ~/.ssh/id_ed25519'
# alias git-setup='cls; git-agent; git-add'
# alias git-setup=". ~/.ssh/git-setup.sh"
alias git-clean='git clean -fdx'
# alias git-new-branch='cls; git checkout -b'
git-new-branch(){
	if [ -z "$1" ]; then
		echo "Error: branch name cannot be empty"
		return 1
	fi
	branch_name="$1"

	cls
	git checkout -b $branch_name
}

# -------------------------------------------------------------------
# wt — Worktree management: push, pull, swap
#   wt push <worktree> [switch-to]          Current branch → worktree, main → [switch-to] (default: master)
#   wt pull <worktree>                      Worktree branch → main dir, remove worktree
#   wt swap <worktree> [new-worktree-name]  Swap main dir branch ↔ worktree
#   wt list                                 List all worktrees
# -------------------------------------------------------------------
wt() {
    local WT_DIR="$HOME/worktrees"
    local MAIN_REPO="${MAIN_REPO:-$HOME}"
    if ! git -C "$MAIN_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "wt: \$MAIN_REPO ($MAIN_REPO) is not a git repository. Set MAIN_REPO to your main repo path." >&2
        return 1
    fi
    local action="$1"
    shift 2>/dev/null

    # Helper: get branch name from a repo path
    __wt_branch() { git -C "$1" symbolic-ref --short HEAD 2>/dev/null; }

    # Helper: derive worktree name from branch (strip srajguru/ and category prefix, dash-separate)
    __wt_name_from_branch() {
        echo "$1" | sed 's|^srajguru/||; s|^[^/]*/||; s|/|-|g'
    }

    case "$action" in
        push)
            local wt_name="$1" fallback="${2:-master}"
            if [[ -z "$wt_name" ]]; then
                echo "Usage: wt push <worktree> [switch-to]  (default switch-to: master)"
                return 1
            fi
            local cur_branch
            cur_branch=$(__wt_branch "$MAIN_REPO")
            [[ -z "$cur_branch" ]] && { echo "Error: main repo is in detached HEAD"; return 1; }
            [[ "$cur_branch" == "$fallback" ]] && { echo "Error: already on $fallback"; return 1; }
            echo "push: $cur_branch → ~/worktrees/$wt_name, main → $fallback"
            git -C "$MAIN_REPO" checkout "$fallback" || return 1
            git worktree add "$WT_DIR/$wt_name" "$cur_branch" || return 1
            echo "Done. main=$fallback, worktree=~/worktrees/$wt_name ($cur_branch)"
            ;;
        pull)
            local wt_name="$1"
            if [[ -z "$wt_name" ]]; then
                echo "Usage: wt pull <worktree>"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "Error: no worktree at $wt_path"; return 1; }
            local target_branch
            target_branch=$(__wt_branch "$wt_path")
            [[ -z "$target_branch" ]] && { echo "Error: worktree is in detached HEAD"; return 1; }
            echo "pull: $target_branch → main dir (removing ~/worktrees/$wt_name)"
            git worktree remove "$wt_path" || return 1
            git -C "$MAIN_REPO" checkout "$target_branch" || return 1
            echo "Done. main=$target_branch"
            ;;
        swap)
            local wt_name="$1" new_wt_name="$2"
            if [[ -z "$wt_name" ]]; then
                echo "Usage: wt swap <worktree> [new-worktree-name]"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "Error: no worktree at $wt_path"; return 1; }
            local cur_branch target_branch
            cur_branch=$(__wt_branch "$MAIN_REPO")
            target_branch=$(__wt_branch "$wt_path")
            [[ -z "$cur_branch" ]] && { echo "Error: main repo is in detached HEAD"; return 1; }
            [[ -z "$target_branch" ]] && { echo "Error: worktree is in detached HEAD"; return 1; }
            [[ -z "$new_wt_name" ]] && new_wt_name=$(__wt_name_from_branch "$cur_branch")
            echo "swap: main ($cur_branch) ↔ ~/worktrees/$wt_name ($target_branch)"
            echo "  main → $target_branch"
            echo "  ~/worktrees/$new_wt_name → $cur_branch"
            git worktree remove "$wt_path" || return 1
            git -C "$MAIN_REPO" checkout "$target_branch" || return 1
            git worktree add "$WT_DIR/$new_wt_name" "$cur_branch" || return 1
            echo "Done."
            ;;
        list|ls)
            git -C "$MAIN_REPO" worktree list
            ;;
        *)
            cat <<'USAGE'
Usage: wt <command> [args]

Commands:
  push <worktree> [switch-to]          Current branch → worktree, main → [switch-to] (default: master)
  pull <worktree>                      Worktree branch → main dir, remove worktree
  swap <worktree> [new-worktree-name]  Swap main dir branch ↔ worktree
  list                                 List all worktrees
USAGE
            return 1
            ;;
    esac
}

# cd-wt — Quick cd to a worktree by directory name or branch name
cd-wt() {
    local WT_DIR="$HOME/worktrees"
    local MAIN_REPO="${MAIN_REPO:-$HOME}"
    if ! git -C "$MAIN_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "cd-wt: \$MAIN_REPO ($MAIN_REPO) is not a git repository. Set MAIN_REPO to your main repo path." >&2
        return 1
    fi
    local target="$1"

    if [[ -z "$target" ]]; then
        git -C "$MAIN_REPO" worktree list
        return 0
    fi

    # Match by main-repo basename or any worktree directory name
    if [[ "$target" == "$(basename "$MAIN_REPO")" || "$target" == "main" ]]; then
        cd "$MAIN_REPO"
        return 0
    fi
    if [[ -d "$WT_DIR/$target" ]]; then
        cd "$WT_DIR/$target"
        return 0
    fi

    # Match by branch name — find the worktree that has this branch checked out
    local wt_path
    wt_path=$(git -C "$MAIN_REPO" worktree list --porcelain | awk -v branch="$target" '
        /^worktree /{path=$2}
        /^branch refs\/heads\//{sub("refs/heads/","",$2); if($2==branch) print path}
    ')
    if [[ -n "$wt_path" ]]; then
        cd "$wt_path"
        return 0
    fi

    echo "Error: no worktree matching '$target'"
    return 1
}

# tmux
# alias tmux-new='tmux new -A -s'
tmux-new(){
	if [ -z "$1" ]; then
		echo "Error: session name cannot be empty"
		return 1
	fi

	session_name="$1"
	tmux new -A -s $session_name
}

tmux-reset(){
	echo "Resetting tmux..."
	echo "Existing session(s):"
	if [ -z "$1" ]; then
		tmux ls
		tmux kill-server
		pkill -9 tmux
		tmux ls
	fi
	session_name="${1:-test_session}"

	tmux ls | grep $session_name
	tmux kill-session -t $session_name

	echo "Create new session:"
	tmux new-session -d -s $session_name
	tmux send-keys -t $session_name:0.0 C-z "${TMUX_RESET_CMD:-clear}" Enter
	tmux ls | grep $session_name	

	if [ -z "$1" ]; then
		tmux ls	
		sleep 10	
		echo "Killing temp test_session..."
		tmux kill-session -t $session_name
		tmux ls
	fi
}


# Kill the tmux server, then install/update all TPM plugins from a plain shell.
# Must be run from OUTSIDE tmux — kill-server kicks you out of the current
# shell otherwise. After it returns, start fresh with `tmux` or `tmux-new`.
tmux-refresh() {
    if [ -n "$TMUX" ]; then
        echo "tmux-refresh: detach first (prefix + d), then re-run from a plain shell." >&2
        return 1
    fi
    local tpm_bin="$HOME/.tmux/plugins/tpm/bin"
    if [ ! -x "$tpm_bin/install_plugins" ]; then
        echo "tmux-refresh: TPM not installed at $tpm_bin." >&2
        echo "  Run ~/dotfiles/bootstrap.sh first." >&2
        return 1
    fi
    if tmux info >/dev/null 2>&1; then
        echo "Killing tmux server..."
        tmux kill-server
    fi
    echo "Installing missing plugins..."
    "$tpm_bin/install_plugins" || return 1
    echo "Updating all plugins..."
    "$tpm_bin/update_plugins" all || return 1
    echo "Done. Start tmux with 'tmux' or 'tmux-new <name>'."
}


# Send a command to tmux sessions
# Usage:
#   tmux-send-all "echo hello"          # send to active pane of every session
#   tmux-send-all -a "make build"       # send to ALL panes in ALL sessions
#   tmux-send-all --idle "runset"       # send only to idle zsh panes (safe for Claude/vim)
#   tmux-send-all --redraw              # USR1 refresh all idle zsh prompts
tmux-send-all() {
    local to_all_panes=0
    if [ "$1" = "-a" ]; then
        to_all_panes=1
        shift
    fi

    # Redraw: send USR1 to all idle zsh panes that have a handler (non-disruptive, preserves input)
    if [ "$1" = "--redraw" ]; then
        tmux info >/dev/null 2>&1 || { echo "No tmux server/sessions found."; return 1; }
        tmux list-panes -a -F '#{pane_pid} #{pane_current_command}' \
        | while read -r pid cmd; do
            [[ "$cmd" == "zsh" ]] && _has_usr1_handler "$pid" && kill -USR1 "$pid" 2>/dev/null
        done
        return 0
    fi

    # Idle: only send to panes at a zsh prompt (skips Claude, vim, running commands)
    if [ "$1" = "--idle" ]; then
        shift
        [[ $# -eq 0 ]] && { echo "Error: command cannot be empty"; return 1; }
        local cmd="$*"
        tmux info >/dev/null 2>&1 || { echo "No tmux server/sessions found."; return 1; }
        tmux list-panes -a -F '#{pane_id} #{pane_current_command}' \
        | while read -r pane_id pcmd; do
            [[ "$pcmd" == "zsh" ]] || continue
            tmux send-keys -t "$pane_id" -l -- "$cmd"
            tmux send-keys -t "$pane_id" C-m
        done
        return 0
    fi

    if [ $# -eq 0 ]; then
        echo "Error: command cannot be empty"
        return 1
    fi

    local cmd="$*"
    tmux info >/dev/null 2>&1 || { echo "No tmux server/sessions found."; return 1; }

    if [ $to_all_panes -eq 1 ]; then
        # Queue for busy panes (they pick it up on next prompt via _check_deferred_cmd)
        local pending="/tmp/tmux-deferred-cmd"
        local ver=1
        if [[ -f "$pending" ]]; then
            local old_line
            old_line=$(< "$pending") 2>/dev/null
            ver=$(( ${old_line%%|*} + 1 ))
        fi
        echo "${ver}|${cmd}" > "$pending"
        # Run in the sending pane immediately and mark as served
        tmux set-option -p @deferred_version "$ver" 2>/dev/null
        echo "[send-all] running: $cmd"
        eval "$cmd"
        # Send immediately to idle zsh panes, mark them as served
        tmux list-panes -a -F '#{pane_id} #{pane_current_command}' \
        | while read -r pane_id pcmd; do
            [[ "$pcmd" == "zsh" ]] || continue
            tmux set-option -t "$pane_id" -p @deferred_version "$ver" 2>/dev/null
            tmux send-keys -t "$pane_id" -l -- " $cmd"
            tmux send-keys -t "$pane_id" C-m
        done
    else
        tmux list-sessions -F '#S' | while IFS= read -r s; do
            tmux send-keys -t "${s}:" -l -- "$cmd"
            tmux send-keys -t "${s}:" C-m
        done
    fi
}

# -------------------------------------------------------------------
# p10k-branch-prompt-watcher
# Watches all worktrees for branch changes and sends SIGUSR1
# to refresh prompts in affected tmux panes only.
# Runs in foreground — Ctrl-C to stop. Dedicate a tmux pane to it.
# -------------------------------------------------------------------
p10k-branch-prompt-watcher() {
  local main_repo="${1:-${MAIN_REPO:-$HOME}}"
  local interval="${2:-30}"
  main_repo="$(cd "$main_repo" && pwd -P)" || { echo "Error: bad path" >&2; return 1; }
  git -C "$main_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "Error: not a git repo: $main_repo" >&2; return 1; }

  _pane_title "p10k-watcher"
  typeset -A branches

  __branch_of() {
    git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null \
      || echo "detached@$(git -C "$1" rev-parse --short HEAD 2>/dev/null)"
  }

  # Initialize state for all worktrees
  while IFS= read -r wt; do
    branches[$wt]="$(__branch_of "$wt")"
    echo "[$(date +%H:%M:%S)] Watching $wt @ ${branches[$wt]}"
  done < <(git -C "$main_repo" worktree list --porcelain | awk '/^worktree /{print $2}')

  echo "[$(date +%H:%M:%S)] Watcher running (every ${interval}s). Ctrl-C to stop."

  trap 'echo; echo "Watcher stopped."; return 0' INT
  while :; do
    sleep "$interval"
    # Re-discover worktrees each cycle (picks up new ones automatically)
    while IFS= read -r wt; do
      cur="$(__branch_of "$wt")"
      if [[ -n "${branches[$wt]:-}" && "$cur" != "${branches[$wt]}" ]]; then
        echo "[$(date +%H:%M:%S)] $wt: ${branches[$wt]} -> $cur"
        _refresh_panes_for_path "$wt"
      fi
      branches[$wt]="$cur"
    done < <(git -C "$main_repo" worktree list --porcelain | awk '/^worktree /{print $2}')
  done
}

# -------------------------------------------------------------------
# stop-p10k-branch-prompt-watcher (legacy — use Ctrl-C for foreground watcher)
# -------------------------------------------------------------------
stop-p10k-branch-prompt-watcher() {
  if [[ -f /tmp/p10k-branch-prompt-watcher.pid ]]; then
    local pid
    pid=$(< /tmp/p10k-branch-prompt-watcher.pid)
    if kill "$pid" >/dev/null 2>&1; then
      echo "Stopped watcher (pid $pid)"
    else
      echo "Watcher not running (stale pid file?)"
    fi
    rm -f /tmp/p10k-branch-prompt-watcher.pid
  else
    echo "No background watcher running. (Foreground watcher: use Ctrl-C)"
  fi
}


# test_func(){
# 	output=$(tmux ls)
# 	if [[ $output == *"no server running"* ]]; then
#       echo "Command succeeded"
#     else
#       echo "Command failed"
#     fi
# }

# utility
alias netcheck='cls; netstat -tulpn'

# -------------------------------------------------------------------
# Tab completions
# -------------------------------------------------------------------
if [ -n "$ZSH_VERSION" ] && (( $+functions[compdef] )); then
    # wt: subcommands, worktree names, branch names
    _wt() {
        if (( CURRENT == 2 )); then
            local -a vals disp
            vals=(push pull swap list)
            disp=(
                "push  -- Current branch → worktree, main → switch-to"
                "pull  -- Worktree branch → main dir"
                "swap  -- Swap main dir branch ↔ worktree"
                "list  -- List all worktrees"
            )
            compadd -l -d disp -a vals
            return
        fi
        case "${words[2]}" in
            pull|swap)
                if (( CURRENT == 3 )); then
                    local -a wts
                    wts=(${(@f)"$(ls -1 "$HOME/worktrees" 2>/dev/null)"})
                    compadd -a wts
                fi
                ;;
            push)
                if (( CURRENT == 4 )); then
                    local -a branches
                    branches=(${(@f)"$(git -C "${MAIN_REPO:-$HOME}" branch --format='%(refname:short)' 2>/dev/null)"})
                    compadd -a branches
                fi
                ;;
        esac
    }
    zstyle ':completion:*:*:wt:*' menu select
    compdef _wt wt

    # cd-wt: worktree directory names + branch names with menu select
    _cd_wt() {
        local -a vals disp
        local MAIN_REPO="${MAIN_REPO:-$HOME}"
        local wt_path="" wt_branch="" wt_name=""
        while IFS= read -r line; do
            if [[ "$line" == worktree\ * ]]; then
                wt_path="${line#worktree }"
            elif [[ "$line" == branch\ refs/heads/* ]]; then
                wt_branch="${line#branch refs/heads/}"
            elif [[ -z "$line" && -n "$wt_path" ]]; then
                if [[ "$wt_path" == "$MAIN_REPO" ]]; then
                    wt_name=$(basename "$MAIN_REPO")
                else
                    wt_name="${wt_path##*/}"
                fi
                vals+=("$wt_name")
                disp+=("$wt_name  -- ${wt_branch:-detached}")
                if [[ -n "$wt_branch" ]]; then
                    vals+=("$wt_branch")
                    disp+=("$wt_branch  -- $wt_name")
                fi
                wt_path="" wt_branch="" wt_name=""
            fi
        done < <(git -C "$MAIN_REPO" worktree list --porcelain; echo)
        compadd -l -d disp -a vals
    }
    zstyle ':completion:*:*:cd-wt:*' menu select
    compdef _cd_wt cd-wt

    # tmux-new: complete existing session names
    _tmux_new() {
        local -a sessions
        sessions=(${(@f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
        compadd -a sessions
    }
    zstyle ':completion:*:*:tmux-new:*' menu select
    zstyle ':completion:*:*:tmux-reset:*' menu select
    compdef _tmux_new tmux-new

    # tmux-reset: complete existing session names
    compdef _tmux_new tmux-reset

elif [ -n "$BASH_VERSION" ]; then
    _wt_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local subcmd="${COMP_WORDS[1]}"
        if (( COMP_CWORD == 1 )); then
            COMPREPLY=($(compgen -W "push pull swap list" -- "$cur"))
            return
        fi
        case "$subcmd" in
            pull|swap)
                if (( COMP_CWORD == 2 )); then
                    COMPREPLY=($(compgen -W "$(ls -1 "$HOME/worktrees" 2>/dev/null)" -- "$cur"))
                fi
                ;;
            push)
                if (( COMP_CWORD == 3 )); then
                    COMPREPLY=($(compgen -W "$(git -C "${MAIN_REPO:-$HOME}" branch --format='%(refname:short)' 2>/dev/null)" -- "$cur"))
                fi
                ;;
        esac
    }
    complete -F _wt_completion wt

    _cd_wt_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local MAIN_REPO="${MAIN_REPO:-$HOME}"
        local words="$(basename "$MAIN_REPO")"
        [[ -d "$HOME/worktrees" ]] && words="$words $(ls -1 "$HOME/worktrees" 2>/dev/null)"
        words="$words $(git -C "$MAIN_REPO" worktree list --porcelain 2>/dev/null | awk '/^branch refs\/heads\//{sub("refs/heads/","",$2); print $2}')"
        COMPREPLY=($(compgen -W "$words" -- "$cur"))
    }
    complete -F _cd_wt_completion cd-wt

    _tmux_session_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -W "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" -- "$cur"))
    }
    complete -F _tmux_session_completion tmux-new
    complete -F _tmux_session_completion tmux-reset

fi

# Note: additional aliases can drop into $ZDOTDIR/local/*.zsh and will be auto-sourced.