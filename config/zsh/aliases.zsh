
# general
alias git=hub
alias p10k-wizard='p10k configure'
export HISTTIMEFORMAT="%d/%m/%y %T "
export PATH=/home/srajguru/.local/bin:$PATH

# rbenv (ruby version manager). Builds ruby from source into ~/.rbenv; shims
# under ~/.rbenv/shims dispatch to the active version. Skipped if rbenv isn't
# installed yet (bootstrap step 5 hasn't run, or this machine doesn't need it).
if [ -d "$HOME/.rbenv" ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  if command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init - zsh)"
  fi
fi

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
# _git_resolve_ref — resolve a ref to its type, fetching if needed.
# Echoes one of: local | remote:<remote> | tag | sha
# Resolution order: local branch → remote branch (auto-fetch) → tag
# (auto-fetch) → SHA (hex regex + rev-parse --verify <ref>^{commit}).
# Usage: _git_resolve_ref <ref> [remote] [repo-path]
# -------------------------------------------------------------------
_git_resolve_ref() {
    local ref="$1" remote="${2:-origin}" repo="${3:-.}"
    if [[ -z "$ref" ]]; then
        echo "Error: ref cannot be empty" >&2
        return 1
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$ref"; then
        echo "local"
        return 0
    fi
    if ! git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$ref"; then
        git -C "$repo" fetch "$remote" "+refs/heads/${ref}:refs/remotes/${remote}/${ref}" >/dev/null 2>&1 || true
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$ref"; then
        echo "remote:$remote"
        return 0
    fi
    if ! git -C "$repo" show-ref --verify --quiet "refs/tags/$ref"; then
        git -C "$repo" fetch "$remote" "tag" "$ref" >/dev/null 2>&1 || true
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/tags/$ref"; then
        echo "tag"
        return 0
    fi
    if [[ "$ref" =~ ^[0-9a-f]{4,40}$ ]] \
       && git -C "$repo" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
        echo "sha"
        return 0
    fi
    echo "Error: ref '$ref' not found locally, on $remote, as tag, or as commit SHA" >&2
    return 1
}

# -------------------------------------------------------------------
# _ensure_tracking_refspec — ensure remote.<r>.fetch covers <branch> so
# `<branch>@{u}` resolves. If not, prompt the user for the refspec
# pattern to add (exact / parent-dir wildcard / top-level wildcard /
# skip), persist via `git config --add`, and refetch.
# Usage: _ensure_tracking_refspec <repo-path> <remote> <branch>
# -------------------------------------------------------------------
_ensure_tracking_refspec() {
    local repo="$1" remote="$2" branch="$3"
    if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "${branch}@{u}" >/dev/null 2>&1; then
        return 0
    fi
    local wildcard_specific="" wildcard_broad=""
    if [[ "$branch" == */* ]]; then
        wildcard_broad="${branch%%/*}/*"
        # Specific: drop only the last segment (e.g., develop/mq-zr10.1 → develop/*)
        wildcard_specific="${branch%/*}/*"
        # If branch has only one slash, specific == broad
        [[ "$wildcard_specific" == "$wildcard_broad" ]] && wildcard_specific=""
    fi
    print -u2 "Branch '$branch' is not covered by any remote.${remote}.fetch refspec."
    print -u2 "Choose how to make it trackable:"
    print -u2 "  1) Exact:  +refs/heads/$branch:refs/remotes/$remote/$branch"
    local next_idx=2 idx_specific="" idx_broad="" idx_custom
    if [[ -n "$wildcard_specific" ]]; then
        idx_specific=$next_idx
        print -u2 "  $idx_specific) Parent: +refs/heads/$wildcard_specific:refs/remotes/$remote/$wildcard_specific"
        next_idx=$((next_idx + 1))
    fi
    if [[ -n "$wildcard_broad" ]]; then
        idx_broad=$next_idx
        print -u2 "  $idx_broad) Top:    +refs/heads/$wildcard_broad:refs/remotes/$remote/$wildcard_broad"
        next_idx=$((next_idx + 1))
    fi
    idx_custom=$next_idx
    print -u2 "  $idx_custom) Custom: type your own pattern (e.g., develop/mq-* or release/*)"
    print -u2 "  s) Skip (branch won't auto-fetch)"
    local reply
    printf "Choice [1]: " >&2
    read -r reply
    reply="${reply:-1}"
    local refspec=""
    case "$reply" in
        1) refspec="+refs/heads/$branch:refs/remotes/$remote/$branch" ;;
        s|S)
            print -u2 "Skipped refspec setup."
            return 0 ;;
        *)
            if [[ "$reply" == "$idx_specific" ]]; then
                refspec="+refs/heads/$wildcard_specific:refs/remotes/$remote/$wildcard_specific"
            elif [[ "$reply" == "$idx_broad" ]]; then
                refspec="+refs/heads/$wildcard_broad:refs/remotes/$remote/$wildcard_broad"
            elif [[ "$reply" == "$idx_custom" ]]; then
                local pattern
                printf "Pattern (will be inserted into +refs/heads/<pattern>:refs/remotes/%s/<pattern>): " "$remote" >&2
                read -r pattern
                if [[ -z "$pattern" ]]; then
                    print -u2 "Empty pattern; skipped."
                    return 0
                fi
                # Sanity check: pattern must match the branch.
                if [[ "$pattern" != "$branch" && "$pattern" != *'*'* ]]; then
                    print -u2 "Warning: pattern '$pattern' has no wildcard and isn't '$branch' — it won't cover this branch."
                fi
                refspec="+refs/heads/$pattern:refs/remotes/$remote/$pattern"
            else
                print -u2 "Unknown choice; skipped."
                return 0
            fi
            ;;
    esac
    if [[ -z "$refspec" ]]; then
        print -u2 "No valid refspec for that choice; skipped."
        return 0
    fi
    git -C "$repo" config --add "remote.${remote}.fetch" "$refspec"
    print -u2 "Added refspec to remote.${remote}.fetch: $refspec"
    # Fetch via the new refspec so refs/remotes/${remote}/* is populated.
    git -C "$repo" fetch "$remote" >/dev/null 2>&1 || true
}

# -------------------------------------------------------------------
# git-checkout-ref — checkout a ref, fetching from remote if needed.
# Branches: sets up tracking when the branch only exists on the remote.
# Tags/SHAs: detached HEAD.
# Usage: git-checkout-ref <ref> [remote]   (default remote: origin)
# -------------------------------------------------------------------
git-checkout-ref() {
    if [ -z "$1" ]; then
        echo "Error: ref cannot be empty"
        return 1
    fi
    local ref="$1" remote="${2:-origin}"
    cls
    # Pre-fetch the specific branch so a stale local refs/remotes/<r>/<branch>
    # gets updated. _git_resolve_ref only fetches when the ref is missing
    # entirely, so without this we'd silently check out an old tip.
    git fetch "$remote" "+refs/heads/${ref}:refs/remotes/${remote}/${ref}" 2>/dev/null || true
    local source
    source=$(_git_resolve_ref "$ref" "$remote") || return 1
    case "$source" in
        local)
            git checkout "$ref"
            ;;
        remote:*)
            # Use the explicit refs/remotes/... path as start-point so checkout
            # works even when remote.<remote>.fetch refspecs don't map this
            # branch (--track validates against refspecs and rejects unmatched
            # upstreams with "starting point ... is not a branch"). Then set
            # tracking via config directly, and ensure a fetch refspec covers
            # the branch so `<branch>@{u}` resolves on future operations.
            local r="${source#remote:}"
            git checkout --no-track -b "$ref" "refs/remotes/${r}/${ref}" || return 1
            git config "branch.${ref}.remote" "$r"
            git config "branch.${ref}.merge" "refs/heads/${ref}"
            _ensure_tracking_refspec "." "$r" "$ref"
            ;;
        tag)
            git checkout --detach "refs/tags/${ref}"
            ;;
        sha)
            git checkout --detach "$ref"
            ;;
    esac
}

# -------------------------------------------------------------------
# claude — wrapper that ensures ssh-agent has a key before launch.
# Why: ssh-add inside Claude Code hangs (its Bash tool runs non-interactively,
# so the passphrase prompt has no stdin). Catching an empty agent here, in
# the interactive shell, lets ssh-add actually prompt for the passphrase.
# Bypass with `command claude` if you really want to launch without keys.
# -------------------------------------------------------------------
claude() {
    if ! ssh-add -l >/dev/null 2>&1; then
        print -P -u2 "%F{yellow}ssh-agent has no keys; running ssh-add first.%f"
        if ! ssh-add; then
            print -P -u2 "%F{red}ssh-add failed; not launching claude.%f"
            return 1
        fi
    fi
    command claude "$@"
}

# -------------------------------------------------------------------
# wt — Worktree management: push, pull, swap, fork, add, rm, sync, merge, clean, prune
#   wt push <worktree> [switch-to]          Current branch → worktree, main → [switch-to] (default: master)
#   wt pull <worktree>                      Worktree branch → main dir, remove worktree
#   wt swap <worktree> [new-worktree-name]  Swap main dir branch ↔ worktree
#   wt fork --from <ref> --name <branch> [--into <wt>]
#                                           Branch off <ref> (wt/branch/tag/sha) into new or existing worktree
#   wt add <worktree> <ref> [remote]        Add <ref> (branch/tag/sha) as a new worktree
#   wt rm [-f] <worktree>                   Remove worktree (-f to force when dirty); auto-purges its bazel cache
#   wt sync                                 Fetch origin once, fast-forward each worktree's branch to its upstream
#   wt merge <ref> [--into <worktree>]      Merge <ref> (branch/tag/sha) into cwd's worktree or --into target
#   wt clean [--into <worktree>] [-x] [-y]  reset --hard HEAD + git clean -fd. -x: include ignored. -y: skip prompt
#   wt prune [-y] [--sudo]                  Remove bazel output_base dirs for worktrees that no longer exist
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
        fork)
            # wt fork --from <wt|branch|sha|tag> --name <new-branch> [--into <wt>]
            # Resolve --from (worktree-name first → HEAD; else local branch,
            # remote branch w/ auto-fetch, tag w/ auto-fetch, or SHA), then
            # check out into target worktree as a new branch. New worktree if
            # --into is missing / not a directory; in-place (refuses if dirty)
            # if --into points to an existing worktree. --into defaults to
            # __wt_name_from_branch(--name); errors if that derived path
            # already exists.
            local from_ref="" new_branch="" into_name=""
            while (( $# )); do
                case "$1" in
                    --from)
                        from_ref="$2"; shift 2 ;;
                    --from=*)
                        from_ref="${1#--from=}"; shift ;;
                    --name)
                        new_branch="$2"; shift 2 ;;
                    --name=*)
                        new_branch="${1#--name=}"; shift ;;
                    --into)
                        into_name="$2"; shift 2 ;;
                    --into=*)
                        into_name="${1#--into=}"; shift ;;
                    -h|--help)
                        cat <<'FORKHELP'
Usage: wt fork --from <ref> --name <new-branch> [--into <wt-name>]
  Create branch <new-branch> off <ref> in a worktree.

  --from <ref>       worktree name (→ its HEAD), local branch, remote branch
                     (auto-fetch), tag (auto-fetch), or commit SHA.
  --name <branch>    name of the new branch (required).
  --into <wt-name>   target worktree. If existing, in-place checkout (refuses
                     when dirty). If missing, creates new worktree at <ref>.
                     Defaults to a name derived from --name; errors if that
                     derived dir already exists.
FORKHELP
                        return 0 ;;
                    *)
                        echo "wt fork: unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            if [[ -z "$from_ref" || -z "$new_branch" ]]; then
                echo "Usage: wt fork --from <ref> --name <new-branch> [--into <wt-name>]"
                return 1
            fi
            if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$new_branch"; then
                echo "Error: branch '$new_branch' already exists locally" >&2
                return 1
            fi
            local main_basename resolved_ref="" from_label=""
            main_basename=$(basename "$MAIN_REPO")
            # Resolve --from: worktree-name first (matches ~/worktrees/<name>
            # or basename($MAIN_REPO) → its HEAD). Else fall through to
            # _git_resolve_ref for branch / remote / tag / sha.
            if [[ "$from_ref" == "$main_basename" ]]; then
                resolved_ref=$(__wt_branch "$MAIN_REPO")
                [[ -z "$resolved_ref" ]] && resolved_ref=$(git -C "$MAIN_REPO" rev-parse HEAD)
                from_label="wt:$main_basename"
            elif [[ -d "$WT_DIR/$from_ref" ]]; then
                resolved_ref=$(__wt_branch "$WT_DIR/$from_ref")
                [[ -z "$resolved_ref" ]] && resolved_ref=$(git -C "$WT_DIR/$from_ref" rev-parse HEAD)
                from_label="wt:$from_ref"
            else
                local source
                source=$(_git_resolve_ref "$from_ref" "origin" "$MAIN_REPO") || return 1
                case "$source" in
                    local)    resolved_ref="$from_ref"; from_label="$source" ;;
                    remote:*) resolved_ref="refs/remotes/${source#remote:}/$from_ref"; from_label="$source" ;;
                    tag)      resolved_ref="refs/tags/$from_ref"; from_label="$source" ;;
                    sha)      resolved_ref="$from_ref"; from_label="$source" ;;
                esac
            fi
            if [[ -z "$into_name" ]]; then
                into_name=$(__wt_name_from_branch "$new_branch")
                if [[ -d "$WT_DIR/$into_name" || "$into_name" == "$main_basename" ]]; then
                    echo "Error: derived worktree '$into_name' already exists; pass --into <wt>" >&2
                    return 1
                fi
            fi
            local target_path
            if [[ "$into_name" == "$main_basename" ]]; then
                target_path="$MAIN_REPO"
            else
                target_path="$WT_DIR/$into_name"
            fi
            if [[ -d "$target_path" ]]; then
                if [[ -n "$(git -C "$target_path" status --porcelain 2>/dev/null)" ]]; then
                    echo "Error: target worktree is dirty: $target_path" >&2
                    return 1
                fi
                echo "fork: in-place $target_path"
                echo "  base: $resolved_ref ($from_label)"
                echo "  new branch: $new_branch"
                git -C "$target_path" checkout -b "$new_branch" "$resolved_ref" || return 1
            else
                echo "fork: new worktree $target_path"
                echo "  base: $resolved_ref ($from_label)"
                echo "  new branch: $new_branch"
                git -C "$MAIN_REPO" worktree add -b "$new_branch" "$target_path" "$resolved_ref" || return 1
            fi
            echo "Done. worktree=$target_path ($new_branch)"
            ;;
        add)
            local wt_name="$1" ref="$2" remote="${3:-origin}"
            if [[ -z "$wt_name" || -z "$ref" ]]; then
                echo "Usage: wt add <worktree-name> <ref> [remote]  (default remote: origin)"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            if [[ -e "$wt_path" ]]; then
                echo "Error: $wt_path already exists"
                return 1
            fi
            local source
            source=$(_git_resolve_ref "$ref" "$remote" "$MAIN_REPO") || return 1
            echo "add: $ref → ~/worktrees/$wt_name (source: $source)"
            case "$source" in
                local)
                    git -C "$MAIN_REPO" worktree add "$wt_path" "$ref" || return 1
                    ;;
                remote:*)
                    # Use the explicit refs/remotes/... path as start-point so the worktree add
                    # works even when remote.<remote>.fetch refspecs don't map this branch.
                    # Then set tracking via config (--track / --set-upstream-to also check refspecs)
                    # and ensure a permanent fetch refspec covers the branch so `<branch>@{u}`
                    # resolves on future operations.
                    local r="${source#remote:}"
                    git -C "$MAIN_REPO" worktree add --no-track -b "$ref" "$wt_path" "refs/remotes/${r}/${ref}" || return 1
                    git -C "$MAIN_REPO" config "branch.${ref}.remote" "$r"
                    git -C "$MAIN_REPO" config "branch.${ref}.merge" "refs/heads/${ref}"
                    _ensure_tracking_refspec "$MAIN_REPO" "$r" "$ref"
                    ;;
                tag)
                    git -C "$MAIN_REPO" worktree add --detach "$wt_path" "refs/tags/${ref}" || return 1
                    ;;
                sha)
                    git -C "$MAIN_REPO" worktree add --detach "$wt_path" "$ref" || return 1
                    ;;
            esac
            echo "Done. worktree=~/worktrees/$wt_name ($ref)"
            ;;
        rm|remove)
            local force=0 wt_name="$1"
            if [[ "$1" == "-f" || "$1" == "--force" ]]; then
                force=1
                wt_name="$2"
            fi
            if [[ -z "$wt_name" ]]; then
                echo "Usage: wt rm [-f] <worktree>"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "Error: no worktree at $wt_path"; return 1; }
            local target_branch
            target_branch=$(__wt_branch "$wt_path")
            echo "rm: removing ~/worktrees/$wt_name (${target_branch:-detached})"
            if (( force )); then
                git -C "$MAIN_REPO" worktree remove --force "$wt_path" || return 1
            else
                git -C "$MAIN_REPO" worktree remove "$wt_path" || return 1
            fi
            # Purge any bazel output_base whose recorded workspace path
            # (DO_NOT_BUILD_HERE) matches the removed worktree. chmod -R u+w
            # first because bazel sets action outputs read-only. If rm still
            # fails (e.g., not user-owned), surface the error and suggest
            # `wt prune --sudo`.
            local bazel_root="$HOME/.cache/bazel/_bazel_$USER" ob ob_name ws
            if [[ -d "$bazel_root" ]]; then
                for ob in "$bazel_root"/*/(N); do
                    ob_name=$(basename "$ob")
                    [[ "$ob_name" =~ ^[0-9a-f]{32}$ ]] || continue
                    [[ -f "${ob}DO_NOT_BUILD_HERE" ]] || continue
                    ws=$(<"${ob}DO_NOT_BUILD_HERE")
                    if [[ "$ws" == "$wt_path" ]]; then
                        chmod -R u+w "${ob%/}" 2>/dev/null
                        if rm -rf "${ob%/}"; then
                            echo "  purged bazel cache: ${ob%/}"
                        else
                            echo "  failed to purge ${ob%/} (try \`wt prune --sudo\`)" >&2
                        fi
                    fi
                done
            fi
            echo "Done."
            ;;
        list|ls)
            git -C "$MAIN_REPO" worktree list
            ;;
        clean)
            # Discard ALL local changes (staged + unstaged) via git reset --hard
            # HEAD, then remove untracked files/dirs via git clean -fd. The y/N
            # prompt is the explicit-confirmation gate required for the
            # reset --hard step. Defaults to cwd's worktree; --into <name>
            # targets a different one. -x extends git clean to also remove
            # ignored files (build artifacts, node_modules).
            local target_path="" into_name="" extend_ignored=0 assume_yes=0
            while (( $# )); do
                case "$1" in
                    --into)
                        into_name="$2"; shift 2 ;;
                    --into=*)
                        into_name="${1#--into=}"; shift ;;
                    -x|--ignored)
                        extend_ignored=1; shift ;;
                    -y|--yes)
                        assume_yes=1; shift ;;
                    -h|--help)
                        cat <<'CLEANHELP'
Usage: wt clean [--into <worktree>] [-x] [-y]
  Discard ALL local changes (staged + unstaged) via `git reset --hard HEAD`
  and remove untracked files/dirs via `git clean -fd` in the target worktree.
  IRREVERSIBLE.

Options:
  --into <worktree>  Target a specific worktree (default: cwd's worktree)
  -x, --ignored      Also remove ignored files (git clean -fdx)
  -y, --yes          Skip the y/N confirmation prompt
CLEANHELP
                        return 0 ;;
                    *)
                        echo "wt clean: unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            if [[ -n "$into_name" ]]; then
                if [[ "$into_name" == "$(basename "$MAIN_REPO")" ]]; then
                    target_path="$MAIN_REPO"
                else
                    target_path="$WT_DIR/$into_name"
                fi
                [[ -d "$target_path" ]] || { echo "Error: no worktree at $target_path"; return 1; }
            else
                target_path=$(git rev-parse --show-toplevel 2>/dev/null)
                if [[ -z "$target_path" ]]; then
                    echo "wt clean: cwd is not inside a git worktree (use --into <name>)" >&2
                    return 1
                fi
            fi
            local clean_flags="-fd"
            (( extend_ignored )) && clean_flags="-fdx"
            local target_branch
            target_branch=$(__wt_branch "$target_path")
            echo "clean: $target_path (${target_branch:-detached})"
            echo "  staged + unstaged (will be discarded by \`git reset --hard HEAD\`):"
            local tracked
            tracked=$(git -C "$target_path" status --porcelain | grep -v '^??' | sed 's/^.. //')
            if [[ -n "$tracked" ]]; then
                echo "$tracked" | sed 's/^/    /'
            else
                echo "    (none)"
            fi
            echo "  untracked (will be removed by \`git clean ${clean_flags}\`):"
            local untracked
            untracked=$(git -C "$target_path" clean -nd ${clean_flags} 2>/dev/null | sed -n 's/^Would remove //p')
            if [[ -n "$untracked" ]]; then
                echo "$untracked" | sed 's/^/    /'
            else
                echo "    (none)"
            fi
            if [[ -z "$tracked" && -z "$untracked" ]]; then
                echo "Nothing to clean."
                return 0
            fi
            if (( ! assume_yes )); then
                local reply
                printf "Proceed? This is IRREVERSIBLE [y/N] "
                read -r reply
                if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
                    echo "Aborted."
                    return 1
                fi
            fi
            git -C "$target_path" reset --hard HEAD || return 1
            git -C "$target_path" clean ${clean_flags} || return 1
            echo "Done."
            ;;
        prune)
            # Scan bazel output_base dirs (~/.cache/bazel/_bazel_$USER/<32-hex>/)
            # and rm -rf any whose recorded workspace path (DO_NOT_BUILD_HERE)
            # no longer exists on disk. Dirs without DO_NOT_BUILD_HERE are
            # spared (workspace path unknown, can't safely decide). Bazel
            # sets `chmod -R u-w` on action outputs to protect them, so we
            # `chmod -R u+w` before rm. --sudo prepends sudo to chmod + rm
            # if even that fails (e.g., files not owned by $USER).
            local assume_yes=0 use_sudo=0
            while (( $# )); do
                case "$1" in
                    -y|--yes) assume_yes=1; shift ;;
                    --sudo)   use_sudo=1; shift ;;
                    -h|--help)
                        cat <<'PRUNEHELP'
Usage: wt prune [-y] [--sudo]
  Find bazel output_base dirs under ~/.cache/bazel/_bazel_$USER/ whose
  recorded workspace path (DO_NOT_BUILD_HERE) no longer exists on disk,
  chmod -R u+w them, then rm -rf. y/N prompt; -y skips. --sudo prepends
  sudo to chmod and rm for files not owned by $USER. IRREVERSIBLE.
PRUNEHELP
                        return 0 ;;
                    *)
                        echo "wt prune: unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            local bazel_root="$HOME/.cache/bazel/_bazel_$USER"
            if [[ ! -d "$bazel_root" ]]; then
                echo "No bazel cache at $bazel_root"
                return 0
            fi
            local -a orphans orphan_paths
            local d ob_name ws
            for d in "$bazel_root"/*/(N); do
                ob_name=$(basename "$d")
                [[ "$ob_name" =~ ^[0-9a-f]{32}$ ]] || continue
                [[ -f "${d}DO_NOT_BUILD_HERE" ]] || continue
                ws=$(<"${d}DO_NOT_BUILD_HERE")
                [[ -z "$ws" ]] && continue
                [[ -d "$ws" ]] && continue
                orphans+=("${d%/}")
                orphan_paths+=("$ws")
            done
            if (( ${#orphans[@]} == 0 )); then
                echo "Nothing to prune."
                return 0
            fi
            echo "Orphaned bazel output_base dirs (workspace path missing):"
            local i ob_size
            for (( i=1; i<=${#orphans[@]}; i++ )); do
                ob_size=$(du -sh "${orphans[i]}" 2>/dev/null | awk '{print $1}')
                printf "  %s  (was: %s, %s)\n" "${orphans[i]}" "${orphan_paths[i]}" "${ob_size:-?}"
            done
            if (( ! assume_yes )); then
                local reply
                printf "Proceed? rm -rf %d dir(s) [y/N] " "${#orphans[@]}"
                read -r reply
                if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
                    echo "Aborted."
                    return 1
                fi
            fi
            local ob sudo_cmd=""
            (( use_sudo )) && sudo_cmd="sudo"
            local removed=0 failed=0
            for ob in "${orphans[@]}"; do
                $sudo_cmd chmod -R u+w "$ob" 2>/dev/null
                if $sudo_cmd rm -rf "$ob"; then
                    echo "  removed $ob"
                    removed=$((removed + 1))
                else
                    echo "  failed: $ob (try --sudo)" >&2
                    failed=$((failed + 1))
                fi
            done
            echo "Done. Pruned $removed dir(s)$( (( failed )) && echo ", $failed failed" )."
            (( failed )) && return 1
            ;;
        sync)
            # Fetch from origin once (refs/remotes/origin/* is shared across
            # all worktrees via the main repo's .git dir), then fast-forward
            # each worktree's checked-out branch to its upstream. Classifies
            # each wt as up-to-date / ff / ahead / diverged / no-upstream /
            # detached / dirty. Refuses ff on dirty wts.
            case "${1:-}" in
                -h|--help)
                    cat <<'SYNCHELP'
Usage: wt sync
  Single `git fetch origin --prune` from the main repo (shared refs),
  then per-worktree `git merge --ff-only @{u}` on the checked-out
  branch. Skips dirty / detached / upstream-less worktrees. Logs
  diverged or ahead branches without modifying them.
SYNCHELP
                    return 0 ;;
            esac
            echo "[fetch] $MAIN_REPO: git fetch origin --prune"
            git -C "$MAIN_REPO" fetch origin --prune 2>&1 | sed 's/^/  /' || return 1
            local -a wts
            local wt_path
            local synced=0 uptodate=0 ahead=0 diverged=0 no_upstream=0 detached=0 dirty=0
            while IFS= read -r wt_path; do
                [[ -z "$wt_path" ]] && continue
                wts+=("$wt_path")
            done < <(git -C "$MAIN_REPO" worktree list --porcelain | awk '/^worktree /{print $2}')
            for wt_path in $wts; do
                local label
                if [[ "$wt_path" == "$MAIN_REPO" ]]; then
                    label="$(basename "$MAIN_REPO") (main)"
                else
                    label="${wt_path##*/}"
                fi
                if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
                    echo "[dirty] $label"
                    dirty=$((dirty + 1))
                    continue
                fi
                local branch
                branch=$(__wt_branch "$wt_path")
                if [[ -z "$branch" ]]; then
                    echo "[detached] $label"
                    detached=$((detached + 1))
                    continue
                fi
                local upstream
                upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name "${branch}@{u}" 2>/dev/null)
                if [[ -z "$upstream" ]]; then
                    echo "[no-upstream] $label ($branch)"
                    no_upstream=$((no_upstream + 1))
                    continue
                fi
                local local_sha remote_sha
                local_sha=$(git -C "$wt_path" rev-parse HEAD)
                remote_sha=$(git -C "$wt_path" rev-parse "$upstream")
                if [[ "$local_sha" == "$remote_sha" ]]; then
                    echo "[up-to-date] $label ($branch @ $upstream)"
                    uptodate=$((uptodate + 1))
                elif git -C "$wt_path" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
                    echo "[ff] $label ($branch → $upstream)"
                    git -C "$wt_path" merge --ff-only "$upstream" 2>&1 | sed 's/^/  /' || return 1
                    synced=$((synced + 1))
                elif git -C "$wt_path" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
                    echo "[ahead] $label ($branch ahead of $upstream, unpushed commits)"
                    ahead=$((ahead + 1))
                else
                    echo "[diverged] $label ($branch diverged from $upstream)"
                    diverged=$((diverged + 1))
                fi
            done
            echo
            echo "Done. ff=$synced up-to-date=$uptodate ahead=$ahead diverged=$diverged no-upstream=$no_upstream detached=$detached dirty=$dirty"
            ;;
        merge)
            # Merge a ref (local branch, remote branch, tag, or SHA) into the
            # worktree at cwd (default) or the worktree given by --into.
            # Refuses to operate on a dirty worktree. Uses `_git_resolve_ref`
            # for resolution.
            local target_path="" into_name="" branch=""
            while (( $# )); do
                case "$1" in
                    --into)
                        into_name="$2"; shift 2 ;;
                    --into=*)
                        into_name="${1#--into=}"; shift ;;
                    -h|--help)
                        echo "Usage: wt merge <branch> [--into <worktree>]"; return 0 ;;
                    *)
                        if [[ -z "$branch" ]]; then
                            branch="$1"
                        else
                            echo "wt merge: unexpected arg: $1" >&2
                            return 1
                        fi
                        shift ;;
                esac
            done
            if [[ -z "$branch" ]]; then
                echo "Usage: wt merge <branch> [--into <worktree>]"
                return 1
            fi
            if [[ -n "$into_name" ]]; then
                if [[ "$into_name" == "$(basename "$MAIN_REPO")" ]]; then
                    target_path="$MAIN_REPO"
                else
                    target_path="$WT_DIR/$into_name"
                fi
                [[ -d "$target_path" ]] || { echo "Error: no worktree at $target_path"; return 1; }
            else
                target_path=$(git rev-parse --show-toplevel 2>/dev/null)
                if [[ -z "$target_path" ]]; then
                    echo "wt merge: cwd is not inside a git worktree (use --into <name>)" >&2
                    return 1
                fi
            fi
            if [[ -n "$(git -C "$target_path" status --porcelain 2>/dev/null)" ]]; then
                echo "Error: target worktree is dirty: $target_path" >&2
                return 1
            fi
            echo "fetch: origin in $target_path"
            git -C "$target_path" fetch origin --prune || return 1
            local source
            source=$(_git_resolve_ref "$branch" "origin" "$target_path") || return 1
            local ref
            case "$source" in
                local)    ref="$branch" ;;
                remote:*) ref="refs/remotes/${source#remote:}/$branch" ;;
                tag)      ref="refs/tags/$branch" ;;
                sha)      ref="$branch" ;;
            esac
            local target_branch
            target_branch=$(__wt_branch "$target_path")
            echo "merge: $ref ($source) → $target_path (${target_branch:-detached})"
            git -C "$target_path" merge "$ref"
            ;;
        *)
            cat <<'USAGE'
Usage: wt <command> [args]

Commands:
  push <worktree> [switch-to]          Current branch → worktree, main → [switch-to] (default: master)
  pull <worktree>                      Worktree branch → main dir, remove worktree
  swap <worktree> [new-worktree-name]  Swap main dir branch ↔ worktree
  fork --from <ref> --name <branch> [--into <wt>]
                                       Branch off <ref> (wt/branch/tag/sha) into new or existing worktree
  add <worktree> <ref> [remote]        Add <ref> (branch/tag/sha) as a new worktree
  rm [-f] <worktree>                   Remove worktree (-f to force when dirty); auto-purges its bazel cache
  sync                                 Fetch origin once, fast-forward each worktree's branch to its upstream
  merge <ref> [--into <worktree>]      Merge <ref> (branch/tag/sha) into cwd's worktree or --into target
  clean [--into <worktree>] [-x] [-y]  reset --hard HEAD + git clean -fd. -x: include ignored. -y: skip prompt
  prune [-y] [--sudo]                  Remove bazel output_base dirs for worktrees that no longer exist
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
  typeset -A seen
  while :; do
    sleep "$interval"
    seen=()
    # Re-discover worktrees each cycle. New ones get a "Watching" log line;
    # branch changes on known wts trigger a pane refresh.
    while IFS= read -r wt; do
      seen[$wt]=1
      cur="$(__branch_of "$wt")"
      if [[ -z "${branches[$wt]+set}" ]]; then
        echo "[$(date +%H:%M:%S)] Watching $wt @ $cur (new)"
      elif [[ "$cur" != "${branches[$wt]}" ]]; then
        echo "[$(date +%H:%M:%S)] $wt: ${branches[$wt]} -> $cur"
        _refresh_panes_for_path "$wt"
      fi
      branches[$wt]="$cur"
    done < <(git -C "$main_repo" worktree list --porcelain | awk '/^worktree /{print $2}')
    # Drop entries for worktrees that disappeared since last cycle.
    for wt in ${(k)branches}; do
      if [[ -z "${seen[$wt]:-}" ]]; then
        echo "[$(date +%H:%M:%S)] Stopped watching $wt (removed)"
        unset "branches[$wt]"
      fi
    done
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
    # Completion functions for wt / cd-wt / tmux-new / tmux-reset live as
    # autoload #compdef files under $ZDOTDIR/completions/ (prepended to fpath
    # in $ZDOTDIR/.zshenv). compinit picks them up automatically and rebuilds
    # _comps from fpath, so any number of later-sourced rc files calling
    # compinit again can't drop these bindings. Only the menu-select zstyles
    # stay here.
    zstyle ':completion:*:*:wt:*' menu select
    zstyle ':completion:*:*:cd-wt:*' menu select
    zstyle ':completion:*:*:tmux-new:*' menu select
    zstyle ':completion:*:*:tmux-reset:*' menu select

elif [ -n "$BASH_VERSION" ]; then
    _wt_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local subcmd="${COMP_WORDS[1]}"
        if (( COMP_CWORD == 1 )); then
            COMPREPLY=($(compgen -W "push pull swap add rm list" -- "$cur"))
            return
        fi
        case "$subcmd" in
            pull|swap|rm|remove)
                if (( COMP_CWORD == 2 )); then
                    COMPREPLY=($(compgen -W "$(ls -1 "$HOME/worktrees" 2>/dev/null)" -- "$cur"))
                fi
                ;;
            push)
                if (( COMP_CWORD == 3 )); then
                    COMPREPLY=($(compgen -W "$(git -C "${MAIN_REPO:-$HOME}" branch --format='%(refname:short)' 2>/dev/null)" -- "$cur"))
                fi
                ;;
            add)
                if (( COMP_CWORD == 3 )); then
                    COMPREPLY=($(compgen -W "$(git -C "${MAIN_REPO:-$HOME}" branch -a --format='%(refname:short)' 2>/dev/null | sed -e 's|^origin/||' -e '/^HEAD$/d' | sort -u)" -- "$cur"))
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