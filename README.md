# dotfiles

General-purpose machine setup: shell (zsh/tmux/p10k via XDG), general Claude Code + Cursor config, general skills/agents/commands.

Designed to be the always-on baseline. Private/work-specific overlays live in separate repos and plug in via `$ZDOTDIR/local/*.zsh` (auto-sourced) and per-item symlinks under `~/.claude/`.

## Layout

```
ai/                    Claude Code + Cursor (CLAUDE.md, settings.json, skills, agents, commands, scripts, ccstatusline)
config/                Shell/term configs that follow XDG (zsh, tmux, p10k)
home/                  Stragglers that must symlink to $HOME (.zshenv-stub, .bazelrc)
bootstrap.sh           First-time machine setup (apt, tmux from source if < 3.5, oh-my-zsh, p10k, tpm, fonts). Idempotent.
setup.sh               Symlink layer. Run after every pull. Idempotent.
sync.sh                git pull + setup.sh.
```

## New machine setup

```bash
git clone <this-repo> ~/dotfiles
~/dotfiles/bootstrap.sh   # full first-time machine setup; calls setup.sh at the end
```

## After every pull

```bash
~/dotfiles/sync.sh
```

## Tmux: reload config, install/update plugins

The prefix is rebound to `Ctrl+Space` (not the default `Ctrl+B`).

- `Ctrl+Space r` — reload `tmux.conf`
- `Ctrl+Space I` (capital I) — install missing TPM plugins
- `Ctrl+Space U` — update all plugins
- `Ctrl+Space alt+u` — clean plugins no longer in the config

If `tmux.conf` was symlinked while a tmux server was already running, the running sessions won't pick up the new config or plugins until the server is restarted. For a full cycle (kill server, reinstall/update all plugins) from a plain shell — must be run **outside** tmux:

```bash
tmux-refresh
```

Then start fresh with `tmux` or `tmux-new <name>`.

## XDG layout

- `ZDOTDIR=$XDG_CONFIG_HOME/zsh` — `.zshrc`, `.zshenv`, `aliases.zsh` live here. A thin `~/.zshenv` stub sets `ZDOTDIR` and forwards.
- `$XDG_CONFIG_HOME/tmux/tmux.conf` — tmux 3.1+ native support.
- `$XDG_CONFIG_HOME/p10k/p10k.zsh` — sourced explicitly from `.zshrc`.
- `$XDG_CONFIG_HOME/ccstatusline/settings.json` — Claude Code status-line config.
- `~/.bazelrc` stays at `$HOME` (no XDG support).

## Drop-in overlays

`.zshrc` sources every `*.zsh` under `$ZDOTDIR/local/` in lexical order. Any external setup script can symlink its own files there without this repo needing to know about them.

For Claude Code skills/agents/commands, external setup scripts should symlink per-item into `~/.claude/{skills,agents,commands,scripts}/<name>` (per-item, not whole-dir, so multiple sources can coexist).

## Worktree helpers

`config/zsh/aliases.zsh` provides `wt`, `cd-wt`, and a p10k branch-prompt watcher that operate on a "main repo." They use the env var `MAIN_REPO`, falling back to `$HOME` when unset. If you keep your primary monorepo at e.g. `~/code`, set:

```bash
export MAIN_REPO="$HOME/code"
```

(Put it in `$ZDOTDIR/local/<your-overlay>.zsh` or your shell init.) When `MAIN_REPO` is unset and `$HOME` isn't a git repo, the helpers print a "not a git repository" message and return cleanly instead of erroring.

## Cursor (Mac)

Cursor's `keybindings.json` lives in the per-user app config dir (`~/Library/Application Support/Cursor/User/keybindings.json` on macOS) and isn't tracked here — the relevant binding to redo on a fresh Mac is the kitty-protocol Shift+Enter override so multi-line edits work in Claude Code's input. The `~/.cursor/{skills,agents,rules,commands}` content *is* tracked via `setup.sh` symlinks.
