
# general
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

  # Option+Left/Right word-jump. Alt-f/Alt-b are word-nav by default in the
  # emacs keymap; Option+arrow is not, so bind the sequences the terminal sends
  # (captured: iTerm2 "Left Option = Esc+" -> modifier-encoded \e[1;3D / \e[1;3C).
  bindkey '\e[1;3D' backward-word   # Option+Left
  bindkey '\e[1;3C' forward-word    # Option+Right

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

  # Clear pane label when shell returns to prompt (prevents stale labels after command finishes).
  # Set to empty (not -u): only a SET triggers a pane-border redraw — an unset leaves the border
  # showing the last-drawn label. Empty string is falsey in the format, so it renders prefix-only.
  _clear_pane_label() { [ -n "$TMUX" ] && tmux set-option -p @pane_label "" 2>/dev/null; }
  precmd_functions=(${precmd_functions:#_clear_pane_label} _clear_pane_label)

  # Auto-label pane with the command being run; cleared at next prompt by the hook above.
  # $1 is the command as typed; tmux truncates the border text to the pane width on render.
  _set_pane_label_cmd() { [ -n "$TMUX" ] && tmux set-option -p @pane_label "$1" 2>/dev/null; }
  preexec_functions=(${preexec_functions:#_set_pane_label_cmd} _set_pane_label_cmd)

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
    echo "\n\n\n${_CT_PHASE}**** deferred send-all command ****${_CT_RESET}"
    echo "${_CT_INFO}>${_CT_RESET} ${_CT_PATH}$cmd${_CT_RESET}\n"
    eval "$cmd" 2>/dev/null
  }
  precmd_functions=(${precmd_functions:#_check_deferred_cmd} _check_deferred_cmd)
else
  echo "${_CT_BAD}Unknown shell type${_CT_RESET}"
fi

# fzf in tmux popup
export FZF_DEFAULT_OPTS='--tmux center,70%,60%'

# Catppuccin flavor switchers — change both the zsh-syntax-highlighting
# colors AND our own aliases.zsh palette (`_CT_*`, used by wt and friends)
# in lockstep, so a `catppuccin-mocha` invocation retints everything.
alias catppuccin-latte='source ${ZDOTDIR:-$HOME}/catppuccin_latte-zsh-syntax-highlighting.zsh && _ct_init latte'
alias catppuccin-frappe='source ${ZDOTDIR:-$HOME}/catppuccin_frappe-zsh-syntax-highlighting.zsh && _ct_init frappe'
alias catppuccin-macchiato='source ${ZDOTDIR:-$HOME}/catppuccin_macchiato-zsh-syntax-highlighting.zsh && _ct_init macchiato'
alias catppuccin-mocha='source ${ZDOTDIR:-$HOME}/catppuccin_mocha-zsh-syntax-highlighting.zsh && _ct_init mocha'

if [ -x "$(command -v colorls)" ]; then
	alias ls="colorls"
	alias la="colorls -al"
	alias lc='colorls -lA --sd'
	#subl $(dirname $(gem which colorls))/yaml
	source $(dirname $(gem which colorls))/tab_complete.sh
fi

cls(){
	# clear; # <--- uncomment to clear shell on alias commands
	echo "${_CT_INFO}Retaining past shell activity${_CT_RESET}"
}

# -------------------------------------------------------------------
# Catppuccin palette — global ANSI vars used by aliases.zsh functions
# for consistent themed output. 24-bit truecolor; reference:
# https://catppuccin.com/palette
#
# Flavor is selected by `$CATPPUCCIN_FLAVOR` (latte / frappe /
# macchiato / mocha). Default macchiato to match the zsh-syntax-
# highlighting flavor sourced from ~/.zshrc. The runtime switch
# aliases (`catppuccin-<flavor>`, defined further down) call back
# into `_ct_init <flavor>` so our palette stays in sync with the
# syntax-highlighting one.
#
# Two layers:
#   1. Raw flavor tokens (`_CT_<color>`) — every swatch in the
#      currently-active flavor.
#   2. Semantic aliases (`_CT_<role>`) — what we actually mean in
#      output (phase / hdr / ok / warn / bad / info / ref / path /
#      done / prompt). All function code uses these so a palette
#      swap requires changes in one place.
#
# `_ct_init [flavor]` re-binds both layers. Honors `$NO_COLOR` as the
# single opt-out. Called once at source time and again on flavor switch.
# -------------------------------------------------------------------
typeset -g CATPPUCCIN_FLAVOR \
           _CT_RESET _CT_BOLD _CT_DIM _CT_ITALIC \
           _CT_ROSEWATER _CT_FLAMINGO _CT_PINK _CT_MAUVE _CT_RED _CT_MAROON \
           _CT_PEACH _CT_YELLOW _CT_GREEN _CT_TEAL _CT_SKY _CT_SAPPHIRE \
           _CT_BLUE _CT_LAVENDER _CT_TEXT _CT_SUBTEXT0 _CT_OVERLAY1 _CT_OVERLAY0 \
           _CT_SURFACE2 \
           _CT_PHASE _CT_HDR _CT_OK _CT_WARN _CT_BAD _CT_INFO _CT_REF _CT_PATH _CT_SHA _CT_DONE _CT_PROMPT
_ct_init() {
    local flavor="${1:-${CATPPUCCIN_FLAVOR:-macchiato}}"
    # Disable only when explicitly opted out via NO_COLOR. We deliberately
    # do NOT gate on `[[ -t 1 ]]` here: aliases.zsh is sourced from
    # ~/.zshrc, where stdout may already be redirected by oh-my-zsh /
    # plugins, leaving the vars empty for the rest of the session. NO_COLOR
    # remains the supported opt-out; redirect-to-file callers see ANSI in
    # the file and can strip with `sed 's/\x1b\[[0-9;]*m//g'`.
    if [[ -n "$NO_COLOR" ]]; then
        _CT_RESET= _CT_BOLD= _CT_DIM= _CT_ITALIC= \
        _CT_ROSEWATER= _CT_FLAMINGO= _CT_PINK= _CT_MAUVE= _CT_RED= _CT_MAROON= \
        _CT_PEACH= _CT_YELLOW= _CT_GREEN= _CT_TEAL= _CT_SKY= _CT_SAPPHIRE= \
        _CT_BLUE= _CT_LAVENDER= _CT_TEXT= _CT_SUBTEXT0= _CT_OVERLAY1= _CT_OVERLAY0= \
        _CT_SURFACE2= \
        _CT_PHASE= _CT_HDR= _CT_OK= _CT_WARN= _CT_BAD= _CT_INFO= _CT_REF= _CT_PATH= _CT_SHA= _CT_DONE= _CT_PROMPT=
        CATPPUCCIN_FLAVOR="$flavor"
        return
    fi
    local fg=$'\e[38;2;'
    _CT_RESET=$'\e[0m'
    _CT_BOLD=$'\e[1m'
    _CT_DIM=$'\e[2m'
    _CT_ITALIC=$'\e[3m'
    case "$flavor" in
        latte)
            _CT_ROSEWATER="${fg}220;138;120m"
            _CT_FLAMINGO="${fg}221;120;120m"
            _CT_PINK="${fg}234;118;203m"
            _CT_MAUVE="${fg}136;57;239m"
            _CT_RED="${fg}210;15;57m"
            _CT_MAROON="${fg}230;69;83m"
            _CT_PEACH="${fg}254;100;11m"
            _CT_YELLOW="${fg}223;142;29m"
            _CT_GREEN="${fg}64;160;43m"
            _CT_TEAL="${fg}23;146;153m"
            _CT_SKY="${fg}4;165;229m"
            _CT_SAPPHIRE="${fg}32;159;181m"
            _CT_BLUE="${fg}30;102;245m"
            _CT_LAVENDER="${fg}114;135;253m"
            _CT_TEXT="${fg}76;79;105m"
            _CT_SUBTEXT0="${fg}108;111;133m"
            _CT_OVERLAY1="${fg}140;143;161m"
            _CT_OVERLAY0="${fg}156;160;176m"
            _CT_SURFACE2="${fg}172;176;190m"
            ;;
        frappe)
            _CT_ROSEWATER="${fg}242;213;207m"
            _CT_FLAMINGO="${fg}238;190;190m"
            _CT_PINK="${fg}244;184;228m"
            _CT_MAUVE="${fg}202;158;230m"
            _CT_RED="${fg}231;130;132m"
            _CT_MAROON="${fg}234;153;156m"
            _CT_PEACH="${fg}239;159;118m"
            _CT_YELLOW="${fg}229;200;144m"
            _CT_GREEN="${fg}166;209;137m"
            _CT_TEAL="${fg}129;200;190m"
            _CT_SKY="${fg}153;209;219m"
            _CT_SAPPHIRE="${fg}133;193;220m"
            _CT_BLUE="${fg}140;170;238m"
            _CT_LAVENDER="${fg}186;187;241m"
            _CT_TEXT="${fg}198;208;245m"
            _CT_SUBTEXT0="${fg}165;173;206m"
            _CT_OVERLAY1="${fg}131;139;167m"
            _CT_OVERLAY0="${fg}115;121;148m"
            _CT_SURFACE2="${fg}98;104;128m"
            ;;
        macchiato)
            _CT_ROSEWATER="${fg}244;219;214m"
            _CT_FLAMINGO="${fg}240;198;198m"
            _CT_PINK="${fg}245;189;230m"
            _CT_MAUVE="${fg}198;160;246m"
            _CT_RED="${fg}237;135;150m"
            _CT_MAROON="${fg}238;153;160m"
            _CT_PEACH="${fg}245;169;127m"
            _CT_YELLOW="${fg}238;212;159m"
            _CT_GREEN="${fg}166;218;149m"
            _CT_TEAL="${fg}139;213;202m"
            _CT_SKY="${fg}145;215;227m"
            _CT_SAPPHIRE="${fg}125;196;228m"
            _CT_BLUE="${fg}138;173;244m"
            _CT_LAVENDER="${fg}183;189;248m"
            _CT_TEXT="${fg}202;211;245m"
            _CT_SUBTEXT0="${fg}165;173;203m"
            _CT_OVERLAY1="${fg}128;135;162m"
            _CT_OVERLAY0="${fg}110;115;141m"
            _CT_SURFACE2="${fg}91;96;120m"
            ;;
        mocha)
            _CT_ROSEWATER="${fg}245;224;220m"
            _CT_FLAMINGO="${fg}242;205;205m"
            _CT_PINK="${fg}245;194;231m"
            _CT_MAUVE="${fg}203;166;247m"
            _CT_RED="${fg}243;139;168m"
            _CT_MAROON="${fg}235;160;172m"
            _CT_PEACH="${fg}250;179;135m"
            _CT_YELLOW="${fg}249;226;175m"
            _CT_GREEN="${fg}166;227;161m"
            _CT_TEAL="${fg}148;226;213m"
            _CT_SKY="${fg}137;220;235m"
            _CT_SAPPHIRE="${fg}116;199;236m"
            _CT_BLUE="${fg}137;180;250m"
            _CT_LAVENDER="${fg}180;190;254m"
            _CT_TEXT="${fg}205;214;244m"
            _CT_SUBTEXT0="${fg}166;173;200m"
            _CT_OVERLAY1="${fg}127;132;156m"
            _CT_OVERLAY0="${fg}108;112;134m"
            _CT_SURFACE2="${fg}88;91;112m"
            ;;
        *)
            print -u2 -- "${_CT_BAD}_ct_init:${_CT_RESET} unknown flavor '${_CT_REF}$flavor${_CT_RESET}' (use ${_CT_INFO}latte${_CT_RESET}|${_CT_INFO}frappe${_CT_RESET}|${_CT_INFO}macchiato${_CT_RESET}|${_CT_INFO}mocha${_CT_RESET}); falling back to ${_CT_INFO}macchiato${_CT_RESET}"
            _ct_init macchiato
            return
            ;;
    esac
    CATPPUCCIN_FLAVOR="$flavor"
    # Semantic aliases. Roles are intentionally few; tune the right-
    # hand side here rather than at call sites.
    _CT_PHASE="${_CT_BOLD}${_CT_SAPPHIRE}"   # phase markers, action banners
    _CT_HDR="${_CT_BOLD}${_CT_TEXT}"         # section headers, ====== bars
    _CT_OK="${_CT_GREEN}"                    # success states
    _CT_WARN="${_CT_YELLOW}"                 # neutral warnings, ahead, no-upstream
    _CT_BAD="${_CT_RED}"                     # errors, dirty, detached, diverged, failed
    _CT_INFO="${_CT_SKY}"                    # informational hints
    _CT_REF="${_CT_MAUVE}"                   # branch / ref names
    _CT_PATH="${_CT_OVERLAY1}"               # paths, upstream refs, metadata
    _CT_SHA="${_CT_PEACH}"                   # short commit SHAs
    _CT_DONE="${_CT_BOLD}${_CT_GREEN}"       # completion banner
    _CT_PROMPT="${_CT_PEACH}"                # interactive prompts (y/N etc)
    _ct_tool_colors   # keep LS_COLORS / GREP_COLORS / menus in lockstep with the flavor
}
# Strip a `_CT_*` value ($'\e[<sgr>m') down to its bare SGR params (`<sgr>`),
# the form LS_COLORS / GREP_COLORS / zstyle list-colors expect.
_ct_sgr() { local s="${1#$'\e['}"; print -rn -- "${s%m}"; }
# Derive LS_COLORS, GREP_COLORS, and completion-menu list-colors from the
# active catppuccin swatches so `ls`, `grep`, tree, fzf, and tab-completion
# menus all share the prompt's palette. Rebuilt by _ct_init on every flavor
# switch — no separate theme file or generator (e.g. vivid) to keep in sync.
# Under NO_COLOR, _ct_init returns before calling this, so the inherited
# color env is left untouched.
_ct_tool_colors() {
    local d g y r m p t o pk
    d="$(_ct_sgr "$_CT_BLUE")"
    g="$(_ct_sgr "$_CT_GREEN")"    y="$(_ct_sgr "$_CT_YELLOW")"
    r="$(_ct_sgr "$_CT_RED")"      m="$(_ct_sgr "$_CT_MAUVE")"
    p="$(_ct_sgr "$_CT_PEACH")"    t="$(_ct_sgr "$_CT_TEAL")"
    o="$(_ct_sgr "$_CT_OVERLAY1")" pk="$(_ct_sgr "$_CT_PINK")"
    local -a c
    c=(
      "di=01;$d"                        # directory
      "ln=$t"                           # symlink
      "or=01;$r"                        # orphaned (broken) symlink
      "mi=$r"                           # missing link target
      "ex=01;$g"                        # executable
      "pi=$y" "so=$m"                   # fifo / socket
      "bd=$y" "cd=$y"                   # block / char device
      "su=$r" "sg=$r" "ca=$r"           # setuid / setgid / capability
      "tw=01;$d" "ow=01;$d" "st=$d"     # sticky / other-writable dirs
      "*.tar=$p" "*.tgz=$p" "*.gz=$p" "*.zip=$p" "*.xz=$p" "*.zst=$p" "*.bz2=$p" "*.7z=$p" "*.rar=$p"   # archives
      "*.png=$m" "*.jpg=$m" "*.jpeg=$m" "*.gif=$m" "*.bmp=$m" "*.svg=$m" "*.webp=$m" "*.ico=$m"          # images
      "*.mp3=$pk" "*.flac=$pk" "*.wav=$pk" "*.mp4=$pk" "*.mkv=$pk" "*.mov=$pk" "*.webm=$pk"              # audio / video
      "*.pdf=$r" "*.md=$y" "*.json=$y" "*.yaml=$y" "*.yml=$y" "*.toml=$y" "*.txt=$o"                     # docs / data
    )
    export LS_COLORS="${(j.:.)c}"
    # grep: bold peach match, blue filename, green line/byte number, overlay separator.
    export GREP_COLORS="ms=01;${p}:mc=01;${p}:sl=:cx=:fn=${d}:ln=${g}:bn=${g}:se=${o}"
    # Tab-completion menus reuse the freshly-built LS_COLORS.
    zstyle ':completion:*' list-colors "${(@s.:.)LS_COLORS}"
}
_ct_init


# Set tmux pane label (user option @pane_label, preferred over command name in pane border)
_pane_title() {
    [ -n "$TMUX" ] && {
        tmux select-pane -T "$1"
        tmux set-option -p @pane_label "$1"
    }
}

# Persistent pane prefix (tmux @pane_prefix). Border shows "<prefix>: <cmd>".
# Survives across commands (the prompt hook only clears @pane_label, not this).
pane-prefix() {
    [ -n "$TMUX" ] || { echo "${_CT_BAD}pane-prefix:${_CT_RESET} not inside tmux." >&2; return 1; }
    case "$1" in
        "")          tmux show-option -pqv @pane_prefix ;;     # show current
        -c|--clear)  tmux set-option -p @pane_prefix "" ;;     # clear (empty SET → redraws; -u wouldn't)
        *)           tmux set-option -p @pane_prefix "$1" ;;   # set
    esac
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
		echo "${_CT_BAD}Error:${_CT_RESET} branch name cannot be empty"
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
        echo "${_CT_BAD}Error:${_CT_RESET} ref cannot be empty" >&2
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
    echo "${_CT_BAD}Error:${_CT_RESET} ref '$ref' not found locally, on $remote, as tag, or as commit SHA" >&2
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
    # Skip if the branch has no tracking intent (no branch.<n>.merge config).
    # Purely local branches shouldn't trigger a refspec prompt.
    local merge_config
    merge_config=$(git -C "$repo" config --get "branch.${branch}.merge" 2>/dev/null)
    [[ -z "$merge_config" ]] && return 0
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
    # Note: brace every $var that's immediately followed by `:` — zsh
    # treats `$var:r` / `:t` / `:h` / `:e` / `:l` / `:u` as csh-style
    # modifiers, silently stripping characters. The braces make the
    # `:` a literal separator.
    print -u2 -- "${_CT_WARN}Branch '${_CT_REF}${branch}${_CT_RESET}${_CT_WARN}' is not covered by any${_CT_RESET} remote.${remote}.fetch ${_CT_WARN}refspec.${_CT_RESET}"
    print -u2 -- "${_CT_HDR}Choose how to make it trackable:${_CT_RESET}"
    print -u2 -- "  ${_CT_INFO}1${_CT_RESET}) Exact:  ${_CT_PATH}+refs/heads/${branch}:refs/remotes/${remote}/${branch}${_CT_RESET}"
    local next_idx=2 idx_specific="" idx_broad="" idx_custom
    if [[ -n "$wildcard_specific" ]]; then
        idx_specific=$next_idx
        print -u2 -- "  ${_CT_INFO}${idx_specific}${_CT_RESET}) Parent: ${_CT_PATH}+refs/heads/${wildcard_specific}:refs/remotes/${remote}/${wildcard_specific}${_CT_RESET}"
        next_idx=$((next_idx + 1))
    fi
    if [[ -n "$wildcard_broad" ]]; then
        idx_broad=$next_idx
        print -u2 -- "  ${_CT_INFO}${idx_broad}${_CT_RESET}) Top:    ${_CT_PATH}+refs/heads/${wildcard_broad}:refs/remotes/${remote}/${wildcard_broad}${_CT_RESET}"
        next_idx=$((next_idx + 1))
    fi
    idx_custom=$next_idx
    print -u2 -- "  ${_CT_INFO}${idx_custom}${_CT_RESET}) Custom: type your own pattern (e.g., ${_CT_PATH}develop/mq-*${_CT_RESET} or ${_CT_PATH}release/*${_CT_RESET})"
    print -u2 -- "  ${_CT_INFO}s${_CT_RESET}) Skip (branch won't auto-fetch)"
    local reply
    printf "${_CT_PROMPT}Choice [1]:${_CT_RESET} " >&2
    read -r reply
    reply="${reply:-1}"
    local refspec=""
    case "$reply" in
        1) refspec="+refs/heads/${branch}:refs/remotes/${remote}/${branch}" ;;
        s|S)
            print -u2 -- "${_CT_WARN}Skipped refspec setup.${_CT_RESET}"
            return 0 ;;
        *)
            if [[ "$reply" == "$idx_specific" ]]; then
                refspec="+refs/heads/${wildcard_specific}:refs/remotes/${remote}/${wildcard_specific}"
            elif [[ "$reply" == "$idx_broad" ]]; then
                refspec="+refs/heads/${wildcard_broad}:refs/remotes/${remote}/${wildcard_broad}"
            elif [[ "$reply" == "$idx_custom" ]]; then
                local pattern
                printf "${_CT_PROMPT}Pattern${_CT_RESET} (will be inserted into ${_CT_PATH}+refs/heads/<pattern>:refs/remotes/%s/<pattern>${_CT_RESET}): " "$remote" >&2
                read -r pattern
                if [[ -z "$pattern" ]]; then
                    print -u2 -- "${_CT_WARN}Empty pattern; skipped.${_CT_RESET}"
                    return 0
                fi
                # Sanity check: pattern must match the branch.
                if [[ "$pattern" != "$branch" && "$pattern" != *'*'* ]]; then
                    print -u2 -- "${_CT_WARN}Warning: pattern '${pattern}' has no wildcard and isn't '${branch}' — it won't cover this branch.${_CT_RESET}"
                fi
                refspec="+refs/heads/${pattern}:refs/remotes/${remote}/${pattern}"
            else
                print -u2 -- "${_CT_WARN}Unknown choice; skipped.${_CT_RESET}"
                return 0
            fi
            ;;
    esac
    if [[ -z "$refspec" ]]; then
        print -u2 -- "${_CT_WARN}No valid refspec for that choice; skipped.${_CT_RESET}"
        return 0
    fi
    git -C "$repo" config --add "remote.${remote}.fetch" "$refspec"
    print -u2 -- "${_CT_OK}Added refspec${_CT_RESET} to remote.${remote}.fetch: ${_CT_PATH}$refspec${_CT_RESET}"
    # Fetch via the new refspec so refs/remotes/${remote}/* is populated.
    git -C "$repo" fetch "$remote" >/dev/null 2>&1 || true
}

# -------------------------------------------------------------------
# _print_trimmed — print first $1 + last $2 lines of stdin, with a
# `... (N more lines) ...` marker between if total > $1+$2. Each line
# (including the marker) is prefixed with $3.
# Usage: <cmd> | _print_trimmed <head> <tail> <indent>
# -------------------------------------------------------------------
_print_trimmed() {
    local head_count="$1" tail_count="$2" indent="$3"
    awk -v head="$head_count" -v tail="$tail_count" -v indent="$indent" '
      { lines[NR] = $0 }
      END {
        if (NR <= head + tail) {
          for (i = 1; i <= NR; i++) print indent lines[i]
        } else {
          for (i = 1; i <= head; i++) print indent lines[i]
          printf "%s... (%d more lines) ...\n", indent, NR - head - tail
          for (i = NR - tail + 1; i <= NR; i++) print indent lines[i]
        }
      }'
}

# -------------------------------------------------------------------
# _capture_with_color — run a command and capture its output WITH ANSI
# colors preserved. `$(cmd)` makes stdout a pipe, which makes git/hub
# auto-disable colors; `-c color.ui=always` doesn't fix it for progress
# lines or hub's own status lines. Routing through `unbuffer` (expect)
# gives the child a PTY so it emits colors as if running interactively.
# Falls back to a plain capture if `unbuffer` is unavailable.
# Stderr is merged to stdout (so callers don't need their own 2>&1).
# Usage: out=$(_capture_with_color git -C <path> fetch ...)
# -------------------------------------------------------------------
_capture_with_color() {
    if (( $+commands[unbuffer] )); then
        unbuffer "$@" 2>&1
    else
        "$@" 2>&1
    fi
}

# -------------------------------------------------------------------
# _refspecs_covering_branch — list remote.<r>.fetch refspecs whose
# left-side ref pattern matches <branch>. Output: one line per match,
# format `<remote>|<refspec>`.
# Usage: _refspecs_covering_branch <repo-path> <branch>
# -------------------------------------------------------------------
_refspecs_covering_branch() {
    local repo="$1" branch="$2"
    local remote refspec rs lhs pattern
    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue
        while IFS= read -r refspec; do
            [[ -z "$refspec" ]] && continue
            rs="${refspec#+}"
            lhs="${rs%%:*}"
            pattern="${lhs#refs/heads/}"
            # zsh glob match: ${~pattern} enables * as glob in pattern position.
            if [[ "$branch" == ${~pattern} ]]; then
                printf '%s|%s\n' "$remote" "$refspec"
            fi
        done < <(git -C "$repo" config --get-all "remote.${remote}.fetch" 2>/dev/null)
    done < <(git -C "$repo" remote 2>/dev/null)
}

# -------------------------------------------------------------------
# git-checkout-ref — checkout a ref, fetching from remote if needed.
# Branches: sets up tracking when the branch only exists on the remote.
# Tags/SHAs: detached HEAD.
# Usage: git-checkout-ref <ref> [remote]   (default remote: origin)
# -------------------------------------------------------------------
git-checkout-ref() {
    if [ -z "$1" ]; then
        echo "${_CT_BAD}Error:${_CT_RESET} ref cannot be empty"
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
            _ensure_tracking_refspec "." "$remote" "$ref"
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
# ssh-agent key guard (shared by claude / git / wt).
# Why: ssh-add hangs in non-interactive shells (Claude Code's Bash tool,
# scripts, hooks) because the passphrase prompt has no stdin. So only prompt in
# an interactive shell; elsewhere warn and let the caller proceed/fail as it
# would have. Returns 0 if the agent already has a key (or one was just added).
# -------------------------------------------------------------------
_ensure_ssh_key() {
    ssh-add -l >/dev/null 2>&1 && return 0
    if [[ ! -o interactive ]]; then
        print -u2 -- "${_CT_WARN}ssh-agent has no keys (non-interactive; run ssh-setup from a terminal).${_CT_RESET}"
        return 1
    fi
    print -u2 -- "${_CT_WARN}ssh-agent has no keys; running ssh-add first.${_CT_RESET}"
    ssh-add
}

# -------------------------------------------------------------------
# ssh-setup [key-path ...] — one-shot agent + key bootstrap (post-reboot).
# Revives the persistent agent if the cached socket is dead (same logic as
# $ZDOTDIR/.zshenv, whose helper is unset after sourcing), then loads keys:
# no args = plain `ssh-add` (default identities), args = those key files.
# Interactive only — the passphrase prompt hangs without a tty.
# -------------------------------------------------------------------
ssh-setup() {
    setopt local_options no_xtrace no_verbose typeset_silent
    if [[ ! -o interactive ]]; then
        print -u2 -- "${_CT_WARN}ssh-setup needs an interactive shell (passphrase prompt).${_CT_RESET}"
        return 1
    fi
    local env_file="$HOME/.ssh/agent-environment"
    _ssh_setup_alive() {
        [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]] || return 1
        ssh-add -l &>/dev/null
        local ec=$?
        [[ $ec -eq 0 || $ec -eq 1 ]]
    }
    if ! _ssh_setup_alive && [[ -r "$env_file" ]]; then
        source "$env_file" >/dev/null
    fi
    if ! _ssh_setup_alive; then
        print -- "${_CT_PHASE}Starting fresh ssh-agent${_CT_RESET} (${_CT_PATH}${env_file}${_CT_RESET})"
        ssh-agent -s >| "$env_file"
        chmod 600 "$env_file"
        source "$env_file" >/dev/null
    fi
    unset -f _ssh_setup_alive
    local k bad=0
    for k in "$@"; do
        if [[ ! -r "$k" ]]; then
            print -u2 -- "${_CT_BAD}Error:${_CT_RESET} no such key file: ${_CT_PATH}${k}${_CT_RESET}"
            bad=1
        fi
    done
    (( bad )) && return 1
    ssh-add "$@" || return 1
    print -- "${_CT_DONE}Agent keys:${_CT_RESET}"
    ssh-add -l
}

# -------------------------------------------------------------------
# claude — wrapper that ensures ssh-agent has a key before launch.
# Bypass with `command claude` if you really want to launch without keys.
# -------------------------------------------------------------------
claude() {
    if ! _ensure_ssh_key; then
        print -u2 -- "${_CT_BAD}ssh-add failed; not launching claude.${_CT_RESET}"
        return 1
    fi
    command claude "$@"
}

# -------------------------------------------------------------------
# git — ensure an ssh key before NETWORK subcommands, interactive shells only.
# Non-interactive git (Claude Code's Bash tool, scripts, hooks) and all local
# subcommands (status/log/diff/...) pass straight through, so nothing ever
# hangs on a passphrase prompt. The arg scan skips git's global options
# (e.g. `git -C <path> fetch`) to find the real subcommand. Bypass: `command git`.
# -------------------------------------------------------------------
git() {
    if [[ -o interactive ]]; then
        local a sub="" skipnext=0
        for a in "$@"; do
            if (( skipnext )); then skipnext=0; continue; fi
            case "$a" in
                -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--exec-path)
                    skipnext=1 ;;          # value is the next arg
                -*) ;;                     # any other option (incl. --opt=value)
                *)  sub="$a"; break ;;     # first non-option token is the subcommand
            esac
        done
        case "$sub" in
            fetch|pull|push|clone|remote|ls-remote|submodule) _ensure_ssh_key ;;
        esac
    fi
    command git "$@"
}

# -------------------------------------------------------------------
# Dynamic named directories (zsh) for inline repo paths. Expand glued to a
# trailing path, at command time, with no $() and no separate `REPO=...` step:
#     bazel run //... -- --input_csv ~[repo]/experimental/foo/data.csv
#   ~[repo]      -> current git worktree root (git rev-parse --show-toplevel)
#   ~[repo-main] -> the main repo (MAIN_REPO, default $HOME)
# Must be UNQUOTED — tilde expansion does not happen inside double quotes.
# Fine for space-free paths (bazel targets, CSVs). Errors if not in a repo.
# -------------------------------------------------------------------
_zdn_repo() {
    case "$1" in
        n)  # name -> directory
            local dir=""
            case "$2" in
                repo)      dir=$(git rev-parse --show-toplevel 2>/dev/null) ;;
                repo-main) dir="${MAIN_REPO:-$HOME}" ;;
                *)         return 1 ;;
            esac
            [[ -n "$dir" ]] || return 1
            reply=("$dir") ;;
        c)  # completion of the name after ~[
            local expl
            _wanted dynamic-dirs expl 'repo directory' compadd repo repo-main ;;
        *)  return 1 ;;
    esac
}
zsh_directory_name_functions=(${zsh_directory_name_functions:#_zdn_repo} _zdn_repo)

# -------------------------------------------------------------------
# wt — Worktree management: push, pull, swap, fork, add, rm, sync, merge, clean, prune
#   wt push <worktree> [switch-to]          Current branch → worktree, main → [switch-to] (default: master)
#   wt pull <worktree>                      Worktree branch → main dir, remove worktree
#   wt swap <worktree> [new-worktree-name]  Swap main dir branch ↔ worktree
#   wt fork --from <ref> --name <branch> [--into <wt>]
#                                           Branch off <ref> (wt/branch/tag/sha) into new or existing worktree
#   wt add <worktree> <ref> [remote]        Add <ref> (branch/tag/sha) as a new worktree
#   wt rm [-f] <worktree>                   Remove worktree (prompts to force if dirty; -f skips prompt); auto-purges its bazel cache
#   wt sync                                 Fetch origin once + `hub sync` in MAIN_REPO, fast-forward each worktree's branch to its upstream
#   wt merge <ref> [--into <worktree>]      Merge <ref> (branch/tag/sha) into cwd's worktree or --into target
#   wt clean [--into <worktree>] [-x] [-y]  reset --hard HEAD + git clean -fd. -x: include ignored. -y: skip prompt
#   wt prune [-y] [--sudo]                  Remove bazel output_base dirs for worktrees that no longer exist
#   wt list                                 List all worktrees
# -------------------------------------------------------------------
wt() {
    # Defensive: shield the function body from a caller-side `setopt
    # XTRACE`/`VERBOSE` (or `set -x`). Without LOCAL_OPTIONS, any trace
    # state in the surrounding shell leaks in and prints every variable
    # assignment in here (including multi-kilobyte merge outputs).
    # TYPESET_SILENT suppresses zsh's default "var=value" announcement
    # when a `local` redeclares a name that already has a value in the
    # current scope — which happens every iteration of a for loop that
    # carries `local foo` inside its body, dumping the *previous* iter's
    # values between status lines.
    setopt local_options no_xtrace no_verbose typeset_silent
    local WT_DIR="$HOME/worktrees"
    local MAIN_REPO="${MAIN_REPO:-$HOME}"
    if ! git -C "$MAIN_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "${_CT_BAD}wt:${_CT_RESET} \$MAIN_REPO ($MAIN_REPO) is not a git repository. Set MAIN_REPO to your main repo path." >&2
        return 1
    fi
    local action="$1"
    shift 2>/dev/null

    # Network subcommands hit a remote (fetch / hub sync), so ensure the
    # ssh-agent has a key first — otherwise the fetch hangs on a passphrase
    # prompt. The fetch runs via `unbuffer git`, which execs the git binary and
    # bypasses the git() wrapper, so the guard has to live here too.
    case "$action" in
        sync|add|fork|merge) _ensure_ssh_key || return 1 ;;
    esac

    # Helper: get branch name from a repo path
    __wt_branch() { git -C "$1" symbolic-ref --short HEAD 2>/dev/null; }

    # Helper: derive worktree name from branch (strip srajguru/ and category prefix, dash-separate)
    __wt_name_from_branch() {
        echo "$1" | sed 's|^srajguru/||; s|^[^/]*/||; s|/|-|g'
    }

    case "$action" in
        cd|goto)
            # Jump to a worktree by its directory name, "main"/main-repo
            # basename, or a checked-out branch name. cd persists because wt()
            # runs in the calling shell. No arg -> list. (Folded in from the
            # old standalone cd-wt.)
            local target="$1" dest=""
            if [[ -z "$target" ]]; then
                git -C "$MAIN_REPO" worktree list
                return 0
            fi
            if [[ "$target" == "main" || "$target" == "$(basename "$MAIN_REPO")" ]]; then
                dest="$MAIN_REPO"
            elif [[ -d "$WT_DIR/$target" ]]; then
                dest="$WT_DIR/$target"
            else
                dest=$(git -C "$MAIN_REPO" worktree list --porcelain | awk -v b="$target" '
                    /^worktree /{p=$2}
                    /^branch refs\/heads\//{sub("refs/heads/","",$2); if($2==b) print p}')
            fi
            if [[ -z "$dest" ]]; then
                echo "${_CT_BAD}Error:${_CT_RESET} no worktree matching '$target'" >&2
                return 1
            fi
            cd "$dest" || return 1
            [[ -n "$TMUX" ]] && tmux set-option -p @pane_prefix "${PWD:t}" 2>/dev/null
            ;;
        push)
            local wt_name="$1" fallback="${2:-master}"
            if [[ -z "$wt_name" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt push <worktree> [switch-to]  (default switch-to: master)"
                return 1
            fi
            local cur_branch
            cur_branch=$(__wt_branch "$MAIN_REPO")
            [[ -z "$cur_branch" ]] && { echo "${_CT_BAD}Error:${_CT_RESET} main repo is in detached HEAD"; return 1; }
            [[ "$cur_branch" == "$fallback" ]] && { echo "${_CT_BAD}Error:${_CT_RESET} already on $fallback"; return 1; }
            echo "${_CT_PHASE}push:${_CT_RESET} $cur_branch → ~/worktrees/$wt_name, main → $fallback"
            git -C "$MAIN_REPO" checkout "$fallback" || return 1
            git worktree add "$WT_DIR/$wt_name" "$cur_branch" || return 1
            echo "${_CT_DONE}Done.${_CT_RESET} main=$fallback, worktree=~/worktrees/$wt_name ($cur_branch)"
            ;;
        pull)
            local wt_name="$1"
            if [[ -z "$wt_name" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt pull <worktree>"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "${_CT_BAD}Error:${_CT_RESET} no worktree at $wt_path"; return 1; }
            local target_branch
            target_branch=$(__wt_branch "$wt_path")
            [[ -z "$target_branch" ]] && { echo "${_CT_BAD}Error:${_CT_RESET} worktree is in detached HEAD"; return 1; }
            echo "${_CT_PHASE}pull:${_CT_RESET} $target_branch → main dir (removing ~/worktrees/$wt_name)"
            git worktree remove "$wt_path" || return 1
            git -C "$MAIN_REPO" checkout "$target_branch" || return 1
            echo "${_CT_DONE}Done.${_CT_RESET} main=$target_branch"
            ;;
        swap)
            local wt_name="$1" new_wt_name="$2"
            if [[ -z "$wt_name" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt swap <worktree> [new-worktree-name]"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "${_CT_BAD}Error:${_CT_RESET} no worktree at $wt_path"; return 1; }
            local cur_branch target_branch
            cur_branch=$(__wt_branch "$MAIN_REPO")
            target_branch=$(__wt_branch "$wt_path")
            [[ -z "$cur_branch" ]] && { echo "${_CT_BAD}Error:${_CT_RESET} main repo is in detached HEAD"; return 1; }
            [[ -z "$target_branch" ]] && { echo "${_CT_BAD}Error:${_CT_RESET} worktree is in detached HEAD"; return 1; }
            [[ -z "$new_wt_name" ]] && new_wt_name=$(__wt_name_from_branch "$cur_branch")
            echo "${_CT_PHASE}swap:${_CT_RESET} main (${_CT_REF}$cur_branch${_CT_RESET}) ↔ ${_CT_PATH}~/worktrees/$wt_name${_CT_RESET} (${_CT_REF}$target_branch${_CT_RESET})"
            echo "  main → ${_CT_REF}$target_branch${_CT_RESET}"
            echo "  ${_CT_PATH}~/worktrees/$new_wt_name${_CT_RESET} → ${_CT_REF}$cur_branch${_CT_RESET}"
            git worktree remove "$wt_path" || return 1
            git -C "$MAIN_REPO" checkout "$target_branch" || return 1
            git worktree add "$WT_DIR/$new_wt_name" "$cur_branch" || return 1
            echo "${_CT_DONE}Done.${_CT_RESET}"
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
                        echo "${_CT_BAD}wt fork:${_CT_RESET} unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            if [[ -z "$from_ref" || -z "$new_branch" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt fork --from <ref> --name <new-branch> [--into <wt-name>]"
                return 1
            fi
            if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$new_branch"; then
                echo "${_CT_BAD}Error:${_CT_RESET} branch '$new_branch' already exists locally" >&2
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
                    echo "${_CT_BAD}Error:${_CT_RESET} derived worktree '$into_name' already exists; pass --into <wt>" >&2
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
                    echo "${_CT_BAD}Error:${_CT_RESET} target worktree is dirty: $target_path" >&2
                    return 1
                fi
                echo "${_CT_PHASE}fork:${_CT_RESET} in-place ${_CT_PATH}$target_path${_CT_RESET}"
                echo "  base: ${_CT_REF}$resolved_ref${_CT_RESET} (${_CT_PATH}$from_label${_CT_RESET})"
                echo "  new branch: ${_CT_REF}$new_branch${_CT_RESET}"
                git -C "$target_path" checkout -b "$new_branch" "$resolved_ref" || return 1
            else
                echo "${_CT_PHASE}fork:${_CT_RESET} new worktree ${_CT_PATH}$target_path${_CT_RESET}"
                echo "  base: ${_CT_REF}$resolved_ref${_CT_RESET} (${_CT_PATH}$from_label${_CT_RESET})"
                echo "  new branch: ${_CT_REF}$new_branch${_CT_RESET}"
                git -C "$MAIN_REPO" worktree add -b "$new_branch" "$target_path" "$resolved_ref" || return 1
            fi
            # The new branch has no remote counterpart yet. Point its tracking
            # config at origin/<new_branch> (not the base ref, which git may
            # otherwise auto-set as the upstream when forking off a remote
            # branch), then — only if no existing fetch refspec already covers
            # the name — prompt to add one so a later push/pull works under
            # driving's explicit-per-pattern refspecs. No push here; the branch
            # is created locally only.
            git -C "$MAIN_REPO" config "branch.${new_branch}.remote" origin
            git -C "$MAIN_REPO" config "branch.${new_branch}.merge" "refs/heads/${new_branch}"
            # Gate on *origin* coverage specifically (the remote we track): a
            # covering refspec on some other remote doesn't make origin/<new>
            # fetchable. Output rows are "<remote>|<refspec>".
            if ! _refspecs_covering_branch "$MAIN_REPO" "$new_branch" | grep -q '^origin|'; then
                _ensure_tracking_refspec "$MAIN_REPO" origin "$new_branch"
            fi
            echo "${_CT_DONE}Done.${_CT_RESET} worktree=${_CT_PATH}$target_path${_CT_RESET} (${_CT_REF}$new_branch${_CT_RESET}) → tracks ${_CT_REF}origin/$new_branch${_CT_RESET}"
            ;;
        add)
            local wt_name="$1" ref="$2" remote="${3:-origin}"
            if [[ -z "$wt_name" || -z "$ref" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt add <worktree-name> <ref> [remote]  (default remote: origin)"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            if [[ -e "$wt_path" ]]; then
                echo "${_CT_BAD}Error:${_CT_RESET} $wt_path already exists"
                return 1
            fi
            local source
            source=$(_git_resolve_ref "$ref" "$remote" "$MAIN_REPO") || return 1
            echo "${_CT_PHASE}add:${_CT_RESET} $ref → ~/worktrees/$wt_name (source: $source)"
            case "$source" in
                local)
                    git -C "$MAIN_REPO" worktree add "$wt_path" "$ref" || return 1
                    _ensure_tracking_refspec "$MAIN_REPO" "$remote" "$ref"
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
            echo "${_CT_DONE}Done.${_CT_RESET} worktree=~/worktrees/$wt_name ($ref)"
            ;;
        rm|remove)
            local force=0 wt_name="$1"
            if [[ "$1" == "-f" || "$1" == "--force" ]]; then
                force=1
                wt_name="$2"
            fi
            if [[ -z "$wt_name" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt rm [-f] <worktree>"
                return 1
            fi
            local wt_path="$WT_DIR/$wt_name"
            [[ -d "$wt_path" ]] || { echo "${_CT_BAD}Error:${_CT_RESET} no worktree at $wt_path"; return 1; }
            local target_branch
            target_branch=$(__wt_branch "$wt_path")
            echo "${_CT_PHASE}rm:${_CT_RESET} removing ~/worktrees/$wt_name (${target_branch:-detached})"
            if (( force )); then
                git -C "$MAIN_REPO" worktree remove --force "$wt_path" || return 1
            elif ! git -C "$MAIN_REPO" worktree remove "$wt_path"; then
                # Plain remove refuses a dirty worktree (modified/untracked files).
                # Offer to force interactively; non-interactive callers just fail.
                [[ -o interactive ]] || return 1
                local ans
                printf "${_CT_PROMPT}Worktree is dirty. Force remove (discards changes)?${_CT_RESET} [y/N]: " >&2
                read -r ans
                [[ "$ans" == [yY]* ]] || { echo "${_CT_BAD}Aborted.${_CT_RESET}" >&2; return 1; }
                git -C "$MAIN_REPO" worktree remove --force "$wt_path" || return 1
            fi
            # Offer to remove fetch refspecs that were covering the removed
            # worktree's branch. Useful when an exact per-branch refspec was
            # added by `_ensure_tracking_refspec` and is no longer needed.
            # Wildcard refspecs covering many branches are listed too — the
            # user picks which (if any) to remove.
            if [[ -n "$target_branch" ]]; then
                local -a matching
                while IFS= read -r line; do
                    [[ -n "$line" ]] && matching+=("$line")
                done < <(_refspecs_covering_branch "$MAIN_REPO" "$target_branch")
                if (( ${#matching[@]} > 0 )); then
                    print -u2 -- "${_CT_HDR}Fetch refspecs currently covering '${_CT_REF}$target_branch${_CT_RESET}${_CT_HDR}':${_CT_RESET}"
                    local i remote refspec
                    for (( i=1; i<=${#matching[@]}; i++ )); do
                        remote="${matching[i]%%|*}"
                        refspec="${matching[i]#*|}"
                        print -u2 -- "  ${_CT_INFO}$i${_CT_RESET}) [${_CT_PATH}$remote${_CT_RESET}] ${_CT_PATH}$refspec${_CT_RESET}"
                    done
                    local reply
                    printf "${_CT_PROMPT}Remove which?${_CT_RESET} [comma-separated indices / all / Enter=skip]: " >&2
                    read -r reply
                    if [[ -n "$reply" && "$reply" != $'\n' ]]; then
                        local -a indices
                        if [[ "$reply" == "all" || "$reply" == "ALL" ]]; then
                            for (( i=1; i<=${#matching[@]}; i++ )); do indices+=("$i"); done
                        else
                            indices=("${(@s:,:)reply}")
                        fi
                        local idx
                        for idx in "${indices[@]}"; do
                            idx="${idx// /}"
                            [[ -z "$idx" ]] && continue
                            if [[ ! "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#matching[@]} )); then
                                print -u2 -- "  ${_CT_BAD}invalid index:${_CT_RESET} $idx"
                                continue
                            fi
                            remote="${matching[idx]%%|*}"
                            refspec="${matching[idx]#*|}"
                            if git -C "$MAIN_REPO" config --unset-all --fixed-value "remote.${remote}.fetch" "$refspec"; then
                                print -u2 -- "  ${_CT_OK}removed:${_CT_RESET} [${_CT_PATH}$remote${_CT_RESET}] ${_CT_PATH}$refspec${_CT_RESET}"
                            else
                                print -u2 -- "  ${_CT_BAD}failed to remove:${_CT_RESET} [${_CT_PATH}$remote${_CT_RESET}] ${_CT_PATH}$refspec${_CT_RESET}" >&2
                            fi
                        done
                    fi
                fi
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
                            echo "  ${_CT_OK}purged bazel cache:${_CT_RESET} ${_CT_PATH}${ob%/}${_CT_RESET}"
                        else
                            echo "  ${_CT_BAD}failed to purge${_CT_RESET} ${_CT_PATH}${ob%/}${_CT_RESET} (try \`wt prune --sudo\`)" >&2
                        fi
                    fi
                done
            fi
            echo "${_CT_DONE}Done.${_CT_RESET}"
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
                        echo "${_CT_BAD}wt clean:${_CT_RESET} unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            if [[ -n "$into_name" ]]; then
                if [[ "$into_name" == "$(basename "$MAIN_REPO")" ]]; then
                    target_path="$MAIN_REPO"
                else
                    target_path="$WT_DIR/$into_name"
                fi
                [[ -d "$target_path" ]] || { echo "${_CT_BAD}Error:${_CT_RESET} no worktree at $target_path"; return 1; }
            else
                target_path=$(git rev-parse --show-toplevel 2>/dev/null)
                if [[ -z "$target_path" ]]; then
                    echo "${_CT_BAD}wt clean:${_CT_RESET} cwd is not inside a git worktree (use --into <name>)" >&2
                    return 1
                fi
            fi
            local clean_flags="-fd"
            (( extend_ignored )) && clean_flags="-fdx"
            local target_branch
            target_branch=$(__wt_branch "$target_path")
            echo "${_CT_PHASE}clean:${_CT_RESET} ${_CT_PATH}$target_path${_CT_RESET} (${_CT_REF}${target_branch:-detached}${_CT_RESET})"
            echo "  ${_CT_HDR}staged + unstaged${_CT_RESET} (will be discarded by \`${_CT_PATH}git reset --hard HEAD${_CT_RESET}\`):"
            local tracked
            tracked=$(git -C "$target_path" status --porcelain | grep -v '^??' | sed 's/^.. //')
            if [[ -n "$tracked" ]]; then
                echo "$tracked" | sed 's/^/    /'
            else
                echo "    ${_CT_PATH}(none)${_CT_RESET}"
            fi
            echo "  ${_CT_HDR}untracked${_CT_RESET} (will be removed by \`${_CT_PATH}git clean ${clean_flags}${_CT_RESET}\`):"
            local untracked
            untracked=$(git -C "$target_path" clean -nd ${clean_flags} 2>/dev/null | sed -n 's/^Would remove //p')
            if [[ -n "$untracked" ]]; then
                echo "$untracked" | sed 's/^/    /'
            else
                echo "    ${_CT_PATH}(none)${_CT_RESET}"
            fi
            if [[ -z "$tracked" && -z "$untracked" ]]; then
                echo "${_CT_OK}Nothing to clean.${_CT_RESET}"
                return 0
            fi
            if (( ! assume_yes )); then
                local reply
                printf "${_CT_PROMPT}Proceed?${_CT_RESET} This is ${_CT_BAD}IRREVERSIBLE${_CT_RESET} [y/N] "
                read -r reply
                if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
                    echo "${_CT_BAD}Aborted.${_CT_RESET}"
                    return 1
                fi
            fi
            git -C "$target_path" reset --hard HEAD || return 1
            git -C "$target_path" clean ${clean_flags} || return 1
            echo "${_CT_DONE}Done.${_CT_RESET}"
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
                        echo "${_CT_BAD}wt prune:${_CT_RESET} unexpected arg: $1" >&2
                        return 1 ;;
                esac
            done
            local bazel_root="$HOME/.cache/bazel/_bazel_$USER"
            if [[ ! -d "$bazel_root" ]]; then
                echo "${_CT_WARN}No bazel cache at${_CT_RESET} ${_CT_PATH}$bazel_root${_CT_RESET}"
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
                echo "${_CT_OK}Nothing to prune.${_CT_RESET}"
                return 0
            fi
            echo "${_CT_HDR}Orphaned bazel output_base dirs${_CT_RESET} (workspace path missing):"
            local i ob_size
            for (( i=1; i<=${#orphans[@]}; i++ )); do
                ob_size=$(du -sh "${orphans[i]}" 2>/dev/null | awk '{print $1}')
                printf "  ${_CT_PATH}%s${_CT_RESET}  (was: ${_CT_PATH}%s${_CT_RESET}, ${_CT_WARN}%s${_CT_RESET})\n" "${orphans[i]}" "${orphan_paths[i]}" "${ob_size:-?}"
            done
            if (( ! assume_yes )); then
                local reply
                printf "${_CT_PROMPT}Proceed?${_CT_RESET} ${_CT_BAD}rm -rf${_CT_RESET} %d dir(s) [y/N] " "${#orphans[@]}"
                read -r reply
                if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
                    echo "${_CT_BAD}Aborted.${_CT_RESET}"
                    return 1
                fi
            fi
            local ob sudo_cmd=""
            (( use_sudo )) && sudo_cmd="sudo"
            local removed=0 failed=0
            for ob in "${orphans[@]}"; do
                $sudo_cmd chmod -R u+w "$ob" 2>/dev/null
                if $sudo_cmd rm -rf "$ob"; then
                    echo "  ${_CT_OK}removed${_CT_RESET} ${_CT_PATH}$ob${_CT_RESET}"
                    removed=$((removed + 1))
                else
                    echo "  ${_CT_BAD}failed:${_CT_RESET} ${_CT_PATH}$ob${_CT_RESET} (try --sudo)" >&2
                    failed=$((failed + 1))
                fi
            done
            echo "${_CT_DONE}Done.${_CT_RESET} Pruned $removed dir(s)$( (( failed )) && echo ", $failed failed" )."
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
  then `hub sync` in MAIN_REPO to ff every local branch that tracks
  a remote, then per-worktree `git merge --ff-only @{u}` on the
  checked-out branch. Skips dirty / detached / upstream-less
  worktrees. Logs diverged or ahead branches without modifying them.
SYNCHELP
                    return 0 ;;
            esac
            # Output is laid out in three indent levels for readability:
            #   L0 (0 spaces): phase markers (`[fetch]`, summary line)
            #   L2 (2 spaces): per-worktree status (`  [ff] label ...`)
            #   L4 (4 spaces): nested command output (fetch detail, merge output)
            # Verbose subcommand output is trimmed via `_print_trimmed` to
            # keep `git merge --ff-only` checkout walls from drowning the
            # per-wt signal.
            # Captures route through `_capture_with_color` (unbuffer/PTY) so
            # git/hub still emit ANSI colors despite stdout being a pipe.
            # CRs from progress lines are flattened to newlines before
            # `_print_trimmed` so head/tail trimming sees them as separate
            # entries rather than one giant line.
            # Uses the catppuccin-mocha semantic palette (_CT_*) defined
            # globally at the top of this file.
            echo "${_CT_PHASE}[fetch]${_CT_RESET} ${_CT_PATH}$MAIN_REPO${_CT_RESET}: git fetch origin --prune"
            # Capture output then print, so sed doesn't mask the fetch's exit
            # status (a `git | sed` pipeline yields sed's status).
            local fetch_output fetch_rc
            fetch_output=$(_capture_with_color git -C "$MAIN_REPO" fetch origin --prune)
            fetch_rc=$?
            if [[ -n "$fetch_output" ]]; then
                printf '%s\n' "$fetch_output" | tr '\r' '\n' | _print_trimmed 5 5 "    "
            else
                echo "    ${_CT_PATH}(no updates)${_CT_RESET}"
            fi
            if (( fetch_rc != 0 )); then
                echo "${_CT_BAD}[fetch] failed (rc=$fetch_rc); aborting wt sync${_CT_RESET}" >&2
                return 1
            fi
            # `hub sync` ff's every local branch in MAIN_REPO that tracks a
            # remote (not just the checked-out one). Complements the per-wt
            # ff below, which only touches branches currently checked out
            # somewhere.
            echo "${_CT_PHASE}[hub-sync]${_CT_RESET} ${_CT_PATH}$MAIN_REPO${_CT_RESET}: hub sync"
            local hub_output hub_rc
            hub_output=$(_capture_with_color hub -C "$MAIN_REPO" sync)
            hub_rc=$?
            if [[ -n "$hub_output" ]]; then
                printf '%s\n' "$hub_output" | tr '\r' '\n' | _print_trimmed 5 5 "    "
            else
                echo "    ${_CT_PATH}(all branches up-to-date)${_CT_RESET}"
            fi
            if (( hub_rc != 0 )); then
                echo "${_CT_BAD}[hub-sync] failed (rc=$hub_rc); aborting wt sync${_CT_RESET}" >&2
                return 1
            fi
            echo "${_CT_PHASE}[worktrees]${_CT_RESET}"
            local -a wts
            local wt_path
            # Per-category lists for the grouped summary at the end.
            local -a ff_list uptodate_list ahead_list diverged_list \
                     no_upstream_list detached_list dirty_list
            while IFS= read -r wt_path; do
                [[ -z "$wt_path" ]] && continue
                wts+=("$wt_path")
            done < <(git -C "$MAIN_REPO" worktree list --porcelain | awk '/^worktree /{print $2}')
            # Per-wt metadata block (printed below the status line). Layout
            # is a single 4-space-indented column of `label  value` pairs;
            # labels are dim, values colored per kind (refs mauve, SHAs
            # peach, ahead/behind warn/bad). Helper kept inside wt() so it
            # closes over the _CT_* globals without needing them on PATH.
            _wt_sync_meta() {
                # _wt_sync_meta <key> <value-colored>
                printf '      %s%-9s%s %b\n' "${_CT_PATH}" "$1" "${_CT_RESET}" "$2"
            }
            for wt_path in $wts; do
                local label
                if [[ "$wt_path" == "$MAIN_REPO" ]]; then
                    label="$(basename "$MAIN_REPO") (main)"
                elif [[ "$wt_path" == "$WT_DIR"/* ]]; then
                    # Name relative to WT_DIR, not basename — a worktree whose
                    # path has slashes (e.g. baseline_rl_2026/07/03) must keep
                    # its full sub-path so `wt cd/rm <name>` ($WT_DIR/$name)
                    # round-trips instead of collapsing to the last segment.
                    label="${wt_path#"$WT_DIR"/}"
                else
                    label="${wt_path##*/}"
                fi
                echo "  ${_CT_HDR}===== $label =====${_CT_RESET}"
                if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
                    echo "  ${_CT_BAD}[dirty]${_CT_RESET}"
                    # Break dirty count into staged / unstaged / untracked.
                    # `diff --cached` = index vs HEAD; `diff` = worktree vs
                    # index; `ls-files --others --exclude-standard` =
                    # untracked respecting .gitignore.
                    local n_staged n_unstaged n_untracked
                    n_staged=$(git -C "$wt_path" diff --cached --name-only 2>/dev/null | wc -l)
                    n_unstaged=$(git -C "$wt_path" diff --name-only 2>/dev/null | wc -l)
                    n_untracked=$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null | wc -l)
                    _wt_sync_meta "files" "${_CT_WARN}${n_staged}${_CT_RESET} staged + ${_CT_WARN}${n_unstaged}${_CT_RESET} unstaged + ${_CT_WARN}${n_untracked}${_CT_RESET} untracked"
                    # Even dirty wts get the branch/upstream/sha context so
                    # the user can see how far the dirty state is from
                    # origin. `wt sync` won't ff a dirty wt (refuses), but
                    # the metadata still helps decide what to do.
                    local dirty_branch dirty_upstream dirty_local_short dirty_remote_short dirty_ahead dirty_behind
                    dirty_branch=$(__wt_branch "$wt_path")
                    if [[ -n "$dirty_branch" ]]; then
                        _wt_sync_meta "branch" "${_CT_REF}${dirty_branch}${_CT_RESET}"
                        dirty_upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name "${dirty_branch}@{u}" 2>/dev/null)
                        dirty_local_short=$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)
                        if [[ -n "$dirty_upstream" ]]; then
                            _wt_sync_meta "upstream" "${_CT_REF}${dirty_upstream}${_CT_RESET}"
                            dirty_remote_short=$(git -C "$wt_path" rev-parse --short "$dirty_upstream" 2>/dev/null)
                            dirty_ahead=$(git -C "$wt_path" rev-list --count "${dirty_upstream}..HEAD" 2>/dev/null)
                            dirty_behind=$(git -C "$wt_path" rev-list --count "HEAD..${dirty_upstream}" 2>/dev/null)
                            if [[ "$dirty_local_short" == "$dirty_remote_short" ]]; then
                                _wt_sync_meta "sha" "${_CT_SHA}${dirty_local_short}${_CT_RESET} ${_CT_PATH}(in sync with upstream)${_CT_RESET}"
                            else
                                _wt_sync_meta "local"  "${_CT_SHA}${dirty_local_short}${_CT_RESET} ${_CT_PATH}(ahead ${_CT_WARN}${dirty_ahead}${_CT_PATH})${_CT_RESET}"
                                _wt_sync_meta "remote" "${_CT_SHA}${dirty_remote_short}${_CT_RESET} ${_CT_PATH}(behind ${_CT_WARN}${dirty_behind}${_CT_PATH})${_CT_RESET}"
                            fi
                        else
                            _wt_sync_meta "sha" "${_CT_SHA}${dirty_local_short}${_CT_RESET} ${_CT_PATH}(no upstream)${_CT_RESET}"
                        fi
                    else
                        local dirty_detached
                        dirty_detached=$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)
                        [[ -n "$dirty_detached" ]] && _wt_sync_meta "sha" "${_CT_SHA}${dirty_detached}${_CT_RESET} ${_CT_PATH}(detached)${_CT_RESET}"
                    fi
                    dirty_list+=("$label")
                    continue
                fi
                local branch
                branch=$(__wt_branch "$wt_path")
                if [[ -z "$branch" ]]; then
                    echo "  ${_CT_BAD}[detached]${_CT_RESET}"
                    local detached_sha
                    detached_sha=$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)
                    [[ -n "$detached_sha" ]] && _wt_sync_meta "sha" "${_CT_SHA}${detached_sha}${_CT_RESET}"
                    detached_list+=("$label")
                    continue
                fi
                local upstream
                upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name "${branch}@{u}" 2>/dev/null)
                if [[ -z "$upstream" ]]; then
                    echo "  ${_CT_WARN}[no-upstream]${_CT_RESET} ${_CT_REF}$branch${_CT_RESET}"
                    local local_short
                    local_short=$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)
                    _wt_sync_meta "branch" "${_CT_REF}${branch}${_CT_RESET}"
                    [[ -n "$local_short" ]] && _wt_sync_meta "sha" "${_CT_SHA}${local_short}${_CT_RESET}"
                    no_upstream_list+=("$label ($branch)")
                    continue
                fi
                local local_sha remote_sha local_short remote_short
                local_sha=$(git -C "$wt_path" rev-parse HEAD)
                remote_sha=$(git -C "$wt_path" rev-parse "$upstream")
                local_short="${local_sha[1,8]}"
                remote_short="${remote_sha[1,8]}"
                # ahead/behind counts — relative to upstream. Used to size the
                # "behind N" / "ahead N" hints in the meta block.
                local n_ahead n_behind
                n_ahead=$(git -C "$wt_path" rev-list --count "${upstream}..HEAD" 2>/dev/null)
                n_behind=$(git -C "$wt_path" rev-list --count "HEAD..${upstream}" 2>/dev/null)
                if [[ "$local_sha" == "$remote_sha" ]]; then
                    echo "  ${_CT_OK}[up-to-date]${_CT_RESET} ${_CT_REF}$branch${_CT_RESET} ${_CT_PATH}@ $upstream${_CT_RESET}"
                    _wt_sync_meta "branch"   "${_CT_REF}${branch}${_CT_RESET}"
                    _wt_sync_meta "upstream" "${_CT_REF}${upstream}${_CT_RESET}"
                    _wt_sync_meta "sha"      "${_CT_SHA}${local_short}${_CT_RESET}"
                    uptodate_list+=("$label ($branch)")
                elif git -C "$wt_path" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
                    echo "  ${_CT_OK}[ff]${_CT_RESET} ${_CT_REF}$branch${_CT_RESET} → ${_CT_REF}$upstream${_CT_RESET}"
                    _wt_sync_meta "branch"   "${_CT_REF}${branch}${_CT_RESET}"
                    _wt_sync_meta "upstream" "${_CT_REF}${upstream}${_CT_RESET}"
                    _wt_sync_meta "local"    "${_CT_SHA}${local_short}${_CT_RESET} → ${_CT_SHA}${remote_short}${_CT_RESET} ${_CT_PATH}(behind ${_CT_WARN}${n_behind}${_CT_PATH})${_CT_RESET}"
                    local merge_output merge_rc
                    merge_output=$(_capture_with_color git -C "$wt_path" merge --ff-only "$upstream")
                    merge_rc=$?
                    [[ -n "$merge_output" ]] && printf '%s\n' "$merge_output" | tr '\r' '\n' | _print_trimmed 5 5 "    "
                    if (( merge_rc != 0 )); then
                        echo "  ${_CT_BAD}[ff] failed (rc=$merge_rc); aborting wt sync${_CT_RESET}" >&2
                        return 1
                    fi
                    ff_list+=("$label ($branch)")
                elif git -C "$wt_path" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
                    echo "  ${_CT_WARN}[ahead]${_CT_RESET} ${_CT_REF}$branch${_CT_RESET} ahead of ${_CT_REF}$upstream${_CT_RESET} ${_CT_PATH}(unpushed commits)${_CT_RESET}"
                    _wt_sync_meta "branch"   "${_CT_REF}${branch}${_CT_RESET}"
                    _wt_sync_meta "upstream" "${_CT_REF}${upstream}${_CT_RESET}"
                    _wt_sync_meta "local"    "${_CT_SHA}${local_short}${_CT_RESET} ${_CT_PATH}(ahead ${_CT_WARN}${n_ahead}${_CT_PATH})${_CT_RESET}"
                    _wt_sync_meta "remote"   "${_CT_SHA}${remote_short}${_CT_RESET}"
                    ahead_list+=("$label ($branch)")
                else
                    echo "  ${_CT_BAD}[diverged]${_CT_RESET} ${_CT_REF}$branch${_CT_RESET} ⇄ ${_CT_REF}$upstream${_CT_RESET}"
                    _wt_sync_meta "branch"   "${_CT_REF}${branch}${_CT_RESET}"
                    _wt_sync_meta "upstream" "${_CT_REF}${upstream}${_CT_RESET}"
                    _wt_sync_meta "local"    "${_CT_SHA}${local_short}${_CT_RESET} ${_CT_PATH}(ahead ${_CT_WARN}${n_ahead}${_CT_PATH})${_CT_RESET}"
                    _wt_sync_meta "remote"   "${_CT_SHA}${remote_short}${_CT_RESET} ${_CT_PATH}(behind ${_CT_BAD}${n_behind}${_CT_PATH})${_CT_RESET}"
                    diverged_list+=("$label ($branch)")
                fi
            done
            unset -f _wt_sync_meta
            echo
            echo "${_CT_DONE}Done.${_CT_RESET}"
            # Grouped summary: one block per non-empty category. Categories
            # with zero members are omitted entirely so the summary scales
            # with what actually happened. Category color matches the
            # per-worktree status color used above so eyes can group
            # by hue.
            local _summary_indent="             > "
            _wt_sync_summary_block() {
                local title="$1" color="$2"; shift 2
                (( $# == 0 )) && return
                echo
                echo "${color}***** ${title}=${#}${_CT_RESET}"
                local item
                for item in "$@"; do
                    echo "${_CT_PATH}${_summary_indent}${_CT_RESET}${item}"
                done
            }
            _wt_sync_summary_block "ff"           "$_CT_OK"   "${ff_list[@]}"
            _wt_sync_summary_block "up-to-date"   "$_CT_OK"   "${uptodate_list[@]}"
            _wt_sync_summary_block "ahead"        "$_CT_WARN" "${ahead_list[@]}"
            _wt_sync_summary_block "diverged"     "$_CT_BAD"  "${diverged_list[@]}"
            _wt_sync_summary_block "no-upstream"  "$_CT_WARN" "${no_upstream_list[@]}"
            _wt_sync_summary_block "detached"     "$_CT_BAD"  "${detached_list[@]}"
            _wt_sync_summary_block "dirty"        "$_CT_BAD"  "${dirty_list[@]}"
            unset -f _wt_sync_summary_block
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
                        echo "${_CT_INFO}Usage:${_CT_RESET} wt merge <branch> [--into <worktree>]"; return 0 ;;
                    *)
                        if [[ -z "$branch" ]]; then
                            branch="$1"
                        else
                            echo "${_CT_BAD}wt merge:${_CT_RESET} unexpected arg: $1" >&2
                            return 1
                        fi
                        shift ;;
                esac
            done
            if [[ -z "$branch" ]]; then
                echo "${_CT_INFO}Usage:${_CT_RESET} wt merge <branch> [--into <worktree>]"
                return 1
            fi
            if [[ -n "$into_name" ]]; then
                if [[ "$into_name" == "$(basename "$MAIN_REPO")" ]]; then
                    target_path="$MAIN_REPO"
                else
                    target_path="$WT_DIR/$into_name"
                fi
                [[ -d "$target_path" ]] || { echo "${_CT_BAD}Error:${_CT_RESET} no worktree at $target_path"; return 1; }
            else
                target_path=$(git rev-parse --show-toplevel 2>/dev/null)
                if [[ -z "$target_path" ]]; then
                    echo "${_CT_BAD}wt merge:${_CT_RESET} cwd is not inside a git worktree (use --into <name>)" >&2
                    return 1
                fi
            fi
            if [[ -n "$(git -C "$target_path" status --porcelain 2>/dev/null)" ]]; then
                echo "${_CT_BAD}Error:${_CT_RESET} target worktree is dirty: $target_path" >&2
                return 1
            fi
            echo "${_CT_PHASE}fetch:${_CT_RESET} origin in $target_path"
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
            echo "${_CT_PHASE}merge:${_CT_RESET} $ref ($source) → $target_path (${target_branch:-detached})"
            git -C "$target_path" merge "$ref"
            ;;
        prune-branches)
            # Interactively delete local branches from the CURRENT repo. fzf
            # multi-select (Tab to mark) with a git-log preview; deletes with
            # `git branch -d` (safe) then offers `-D` for any that weren't fully
            # merged. `-f`/`--force` deletes the whole selection with `-D`.
            local force=0
            while (( $# )); do
                case "$1" in
                    -f|--force) force=1; shift ;;
                    -h|--help)
                        echo "${_CT_INFO}Usage:${_CT_RESET} wt prune-branches [-f]   fzf-pick local branches to delete; -f forces -D"
                        return 0 ;;
                    *) echo "${_CT_BAD}wt prune-branches:${_CT_RESET} unexpected arg: $1" >&2; return 1 ;;
                esac
            done
            command -v fzf >/dev/null 2>&1 || { echo "${_CT_BAD}wt prune-branches:${_CT_RESET} fzf not found" >&2; return 1; }
            local repo
            repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
                echo "${_CT_BAD}wt prune-branches:${_CT_RESET} not inside a git repository" >&2; return 1; }
            # Roomier popup than the global default (--tmux ...) and a
            # full-width wrapped preview below the list, capped at a third of
            # the popup height so the branch list stays dominant. Long commit
            # subjects wrap; the log is short and scrollable for the rest.
            local selected fzf_rc
            selected=$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ \
                | fzf -m --tmux center,85%,80% --prompt='delete branch> ' \
                      --preview-window='down,33%,wrap' \
                      --header='Tab=mark  Enter=confirm  (current / worktree-checked-out branches skipped)' \
                      --preview="git -C ${(q)repo} log --oneline --graph --decorate --color=always -12 {} 2>/dev/null")
            fzf_rc=$?
            # fzf: 0=selected, 1=no match, 130=interrupt/ESC → nothing to do.
            # Anything else (2=error, 126/127) is a real failure worth surfacing.
            if (( fzf_rc == 1 || fzf_rc == 130 )); then
                return 0
            elif (( fzf_rc != 0 )); then
                echo "${_CT_BAD}wt prune-branches:${_CT_RESET} fzf exited with $fzf_rc" >&2
                return $fzf_rc
            fi
            [[ -z "$selected" ]] && { echo "${_CT_INFO}wt prune-branches:${_CT_RESET} nothing selected."; return 0; }
            local -a branches unmerged
            branches=("${(f)selected}")
            local b out rc ans
            if (( force )); then
                echo "${_CT_PROMPT}Force-delete (${_CT_WARN}-D${_CT_PROMPT}) ${#branches} branch(es): ${_CT_REF}${branches[*]}${_CT_PROMPT}? [y/N]${_CT_RESET} "
                # Read the confirmation from the terminal, not inherited stdin,
                # so a redirected/piped stdin can't auto-answer a destructive -D.
                read -r ans < /dev/tty
                [[ "$ans" == [yY]* ]] || { echo "${_CT_BAD}Aborted.${_CT_RESET}"; return 1; }
                for b in "${branches[@]}"; do
                    if git -C "$repo" branch -D "$b" >/dev/null 2>&1; then
                        echo "  ${_CT_OK}force-deleted${_CT_RESET} ${_CT_REF}$b${_CT_RESET}"
                    else
                        echo "  ${_CT_BAD}failed${_CT_RESET} ${_CT_REF}$b${_CT_RESET} ${_CT_PATH}(current or checked out in a worktree)${_CT_RESET}"
                    fi
                done
                return 0
            fi
            # Safe pass: -d refuses unmerged branches (collect for the force
            # prompt) and branches that are current / checked out elsewhere.
            for b in "${branches[@]}"; do
                out=$(git -C "$repo" branch -d "$b" 2>&1); rc=$?
                if (( rc == 0 )); then
                    echo "  ${_CT_OK}deleted${_CT_RESET} ${_CT_REF}$b${_CT_RESET}"
                elif [[ "$out" == *"not fully merged"* ]]; then
                    unmerged+=("$b")
                    echo "  ${_CT_WARN}unmerged${_CT_RESET} ${_CT_REF}$b${_CT_RESET} ${_CT_PATH}(not fully merged)${_CT_RESET}"
                else
                    echo "  ${_CT_BAD}skipped${_CT_RESET} ${_CT_REF}$b${_CT_RESET}: ${_CT_PATH}${out#error: }${_CT_RESET}"
                fi
            done
            if (( ${#unmerged} )); then
                echo
                echo "${_CT_PROMPT}${#unmerged} unmerged branch(es): ${_CT_REF}${unmerged[*]}${_CT_PROMPT}. Force-delete (${_CT_WARN}-D${_CT_PROMPT})? [y/N]${_CT_RESET} "
                read -r ans < /dev/tty
                if [[ "$ans" == [yY]* ]]; then
                    for b in "${unmerged[@]}"; do
                        if git -C "$repo" branch -D "$b" >/dev/null 2>&1; then
                            echo "  ${_CT_OK}force-deleted${_CT_RESET} ${_CT_REF}$b${_CT_RESET}"
                        else
                            echo "  ${_CT_BAD}failed${_CT_RESET} ${_CT_REF}$b${_CT_RESET}"
                        fi
                    done
                else
                    echo "${_CT_INFO}Kept unmerged branches.${_CT_RESET}"
                fi
            fi
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
  rm [-f] <worktree>                   Remove worktree (prompts to force if dirty; -f skips prompt); auto-purges its bazel cache
  sync                                 Fetch origin once, fast-forward each worktree's branch to its upstream
  merge <ref> [--into <worktree>]      Merge <ref> (branch/tag/sha) into cwd's worktree or --into target
  clean [--into <worktree>] [-x] [-y]  reset --hard HEAD + git clean -fd. -x: include ignored. -y: skip prompt
  prune [-y] [--sudo]                  Remove bazel output_base dirs for worktrees that no longer exist
  prune-branches [-f]                  fzf-pick local branches to delete (-d, prompts to -D); -f forces -D
  list                                 List all worktrees
USAGE
            return 1
            ;;
    esac
}

# Completion helper (used by _wt): populate the caller's `vals`
# and `disp` arrays with one entry per worktree — value = worktree name,
# display = "name  -- branch" — so every worktree listing looks the same and
# shows a single permutation. Relies on zsh dynamic scoping: the caller must
# declare `local -a vals disp` before calling. Pass --linked to exclude the
# main repo (MAIN_REPO); default includes it (as its basename).
_wt_worktree_compdata() {
    local include_main=1
    [[ "$1" == --linked ]] && include_main=0
    local repo="${MAIN_REPO:-$HOME}"
    local wt_dir="$HOME/worktrees"
    local wt_path="" wt_branch="" wt_name=""
    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            wt_path="${line#worktree }"
        elif [[ "$line" == branch\ refs/heads/* ]]; then
            wt_branch="${line#branch refs/heads/}"
        elif [[ -z "$line" && -n "$wt_path" ]]; then
            if [[ "$wt_path" == "$repo" ]]; then
                wt_name=$(basename "$repo")
                (( include_main )) && { vals+=("$wt_name"); disp+=("$wt_name  -- ${wt_branch:-detached}"); }
            elif [[ "$wt_path" == "$wt_dir"/* ]]; then
                # Name relative to WT_DIR so worktrees with slashes in their
                # path (e.g. baseline_rl_2026/07/03) complete to the full
                # sub-path and round-trip through `wt cd/rm` ($WT_DIR/$name),
                # instead of collapsing to a non-resolvable last segment.
                wt_name="${wt_path#"$wt_dir"/}"
                vals+=("$wt_name"); disp+=("$wt_name  -- ${wt_branch:-detached}")
            else
                wt_name="${wt_path##*/}"
                vals+=("$wt_name"); disp+=("$wt_name  -- ${wt_branch:-detached}")
            fi
            wt_path="" wt_branch="" wt_name=""
        fi
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; echo)
}

# tmux
# alias tmux-new='tmux new -A -s'
tmux-new(){
	if [ -z "$1" ]; then
		echo "${_CT_BAD}Error:${_CT_RESET} session name cannot be empty"
		return 1
	fi

	session_name="$1"
	tmux new -A -s $session_name
}

tmux-reset(){
	echo "${_CT_PHASE}Resetting tmux...${_CT_RESET}"
	echo "${_CT_HDR}Existing session(s):${_CT_RESET}"
	if [ -z "$1" ]; then
		tmux ls
		tmux kill-server
		pkill -9 tmux
		tmux ls
	fi
	session_name="${1:-test_session}"

	tmux ls | grep $session_name
	tmux kill-session -t $session_name

	echo "${_CT_HDR}Create new session:${_CT_RESET}"
	tmux new-session -d -s $session_name
	tmux send-keys -t $session_name:0.0 C-z "${TMUX_RESET_CMD:-clear}" Enter
	tmux ls | grep $session_name

	if [ -z "$1" ]; then
		tmux ls
		sleep 10
		echo "${_CT_WARN}Killing temp test_session...${_CT_RESET}"
		tmux kill-session -t $session_name
		tmux ls
	fi
}


# Kill the tmux server, then install/update all TPM plugins from a plain shell.
# Must be run from OUTSIDE tmux — kill-server kicks you out of the current
# shell otherwise. After it returns, start fresh with `tmux` or `tmux-new`.
tmux-refresh() {
    if [ -n "$TMUX" ]; then
        echo "${_CT_BAD}tmux-refresh:${_CT_RESET} detach first (prefix + d), then re-run from a plain shell." >&2
        return 1
    fi
    local tpm_bin="$HOME/.tmux/plugins/tpm/bin"
    if [ ! -x "$tpm_bin/install_plugins" ]; then
        echo "${_CT_BAD}tmux-refresh:${_CT_RESET} TPM not installed at ${_CT_PATH}$tpm_bin${_CT_RESET}." >&2
        echo "  Run ${_CT_PATH}~/dotfiles/bootstrap.sh${_CT_RESET} first." >&2
        return 1
    fi
    if tmux info >/dev/null 2>&1; then
        echo "${_CT_WARN}Killing tmux server...${_CT_RESET}"
        tmux kill-server
    fi
    echo "${_CT_PHASE}Installing missing plugins...${_CT_RESET}"
    "$tpm_bin/install_plugins" || return 1
    echo "${_CT_PHASE}Updating all plugins...${_CT_RESET}"
    "$tpm_bin/update_plugins" all || return 1
    echo "${_CT_DONE}Done.${_CT_RESET} Start tmux with 'tmux' or 'tmux-new <name>'."
}


# Respawn the current tmux pane with a fresh shell. Heavier than `exec zsh`
# (which inherits tty modes, fds, env, tmux pipe-pane state) — kills the
# inferior process and starts a new one in the same pane. Layout, pane_id,
# and pane history slot are preserved; pty state is reset by tmux.
# Use when one terminal misbehaves (silent stdout, weird stty) but you
# don't want to lose the pane layout.
tmux-respawn() {
    if [ -z "$TMUX" ]; then
        echo "${_CT_BAD}tmux-respawn:${_CT_RESET} not inside tmux." >&2
        return 1
    fi
    # Pass $SHELL explicitly: tmux-resurrect bakes
    # `cat <pane_content_file>; exec <shell>` as the pane's start command,
    # so `respawn-pane -k` without args re-runs that and prints a stale-file
    # cat error when the saved content is gone.
    # `-c "$PWD"` preserves the current directory across respawn.
    tmux respawn-pane -k -c "$PWD" "${SHELL:-zsh}"
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
        [[ $# -eq 0 ]] && { echo "${_CT_BAD}Error:${_CT_RESET} command cannot be empty"; return 1; }
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
        echo "${_CT_BAD}Error:${_CT_RESET} command cannot be empty"
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
        echo "${_CT_PHASE}[send-all]${_CT_RESET} running: ${_CT_PATH}$cmd${_CT_RESET}"
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
  main_repo="$(cd "$main_repo" && pwd -P)" || { echo "${_CT_BAD}Error:${_CT_RESET} bad path" >&2; return 1; }
  git -C "$main_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "${_CT_BAD}Error:${_CT_RESET} not a git repo: $main_repo" >&2; return 1; }

  typeset -A branches

  __branch_of() {
    git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null \
      || echo "detached@$(git -C "$1" rev-parse --short HEAD 2>/dev/null)"
  }

  # Initialize state for all worktrees
  while IFS= read -r wt; do
    branches[$wt]="$(__branch_of "$wt")"
    echo "${_CT_PATH}[$(date +%H:%M:%S)]${_CT_RESET} ${_CT_INFO}Watching${_CT_RESET} ${_CT_PATH}$wt${_CT_RESET} @ ${_CT_REF}${branches[$wt]}${_CT_RESET}"
  done < <(git -C "$main_repo" worktree list --porcelain | awk '/^worktree /{print $2}')

  echo "${_CT_PATH}[$(date +%H:%M:%S)]${_CT_RESET} ${_CT_PHASE}Watcher running${_CT_RESET} (every ${interval}s). Ctrl-C to stop."

  trap 'echo; echo "${_CT_BAD}Watcher stopped.${_CT_RESET}"; return 0' INT
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
        echo "${_CT_PATH}[$(date +%H:%M:%S)]${_CT_RESET} ${_CT_OK}Watching${_CT_RESET} ${_CT_PATH}$wt${_CT_RESET} @ ${_CT_REF}$cur${_CT_RESET} ${_CT_PATH}(new)${_CT_RESET}"
      elif [[ "$cur" != "${branches[$wt]}" ]]; then
        echo "${_CT_PATH}[$(date +%H:%M:%S)]${_CT_RESET} ${_CT_PATH}$wt${_CT_RESET}: ${_CT_REF}${branches[$wt]}${_CT_RESET} -> ${_CT_REF}$cur${_CT_RESET}"
        _refresh_panes_for_path "$wt"
      fi
      branches[$wt]="$cur"
    done < <(git -C "$main_repo" worktree list --porcelain | awk '/^worktree /{print $2}')
    # Drop entries for worktrees that disappeared since last cycle.
    for wt in ${(k)branches}; do
      if [[ -z "${seen[$wt]:-}" ]]; then
        echo "${_CT_PATH}[$(date +%H:%M:%S)]${_CT_RESET} ${_CT_WARN}Stopped watching${_CT_RESET} ${_CT_PATH}$wt${_CT_RESET} (removed)"
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
      echo "${_CT_OK}Stopped watcher${_CT_RESET} (pid ${_CT_PATH}$pid${_CT_RESET})"
    else
      echo "${_CT_WARN}Watcher not running${_CT_RESET} (stale pid file?)"
    fi
    rm -f /tmp/p10k-branch-prompt-watcher.pid
  else
    echo "${_CT_WARN}No background watcher running.${_CT_RESET} (Foreground watcher: use Ctrl-C)"
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
    # Completion functions for wt / tmux-new / tmux-reset live as
    # autoload #compdef files under $ZDOTDIR/completions/ (prepended to fpath
    # in $ZDOTDIR/.zshenv). compinit picks them up automatically and rebuilds
    # _comps from fpath, so any number of later-sourced rc files calling
    # compinit again can't drop these bindings. Only the menu-select zstyles
    # stay here.
    zstyle ':completion:*:*:wt:*' menu select
    zstyle ':completion:*:*:pane-prefix:*' menu select
    zstyle ':completion:*:*:tmux-new:*' menu select
    zstyle ':completion:*:*:tmux-reset:*' menu select
    zstyle ':completion:*:*:ssh-setup:*' menu select

elif [ -n "$BASH_VERSION" ]; then
    _wt_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local subcmd="${COMP_WORDS[1]}"
        if (( COMP_CWORD == 1 )); then
            COMPREPLY=($(compgen -W "cd push pull swap add rm prune-branches list" -- "$cur"))
            return
        fi
        case "$subcmd" in
            pull|swap|rm|remove)
                if (( COMP_CWORD == 2 )); then
                    COMPREPLY=($(compgen -W "$(ls -1 "$HOME/worktrees" 2>/dev/null)" -- "$cur"))
                fi
                ;;
            cd|goto)
                if (( COMP_CWORD == 2 )); then
                    local MAIN_REPO="${MAIN_REPO:-$HOME}"
                    # Worktrees + the main repo only — not local branch names.
                    local words="$(basename "$MAIN_REPO") $(ls -1 "$HOME/worktrees" 2>/dev/null)"
                    COMPREPLY=($(compgen -W "$words" -- "$cur"))
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
            prune-branches)
                if (( COMP_CWORD == 2 )); then
                    COMPREPLY=($(compgen -W "-f --force -h --help" -- "$cur"))
                fi
                ;;
        esac
    }
    complete -F _wt_completion wt

    _tmux_session_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -W "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" -- "$cur"))
    }
    complete -F _tmux_session_completion tmux-new
    complete -F _tmux_session_completion tmux-reset

fi

# Note: additional aliases can drop into $ZDOTDIR/local/*.zsh and will be auto-sourced.