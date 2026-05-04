# --- Persistent ssh-agent ---
# Reuse a long-lived ssh-agent across shells; overrides Cursor's per-session
# forwarded SSH_AUTH_SOCK, which goes stale across reconnects and forces
# passphrase re-entry. Lives in .zshenv so it applies to non-interactive
# shells too (Claude Code's Bash tool, scripts, etc.). After a reboot,
# run `ssh-add` once to load your key.
_ssh_agent_env="$HOME/.ssh/agent-environment"
_ssh_agent_alive() {
    [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]] || return 1
    ssh-add -l &>/dev/null
    local ec=$?
    [[ $ec -eq 0 || $ec -eq 1 ]]
}
[[ -r "$_ssh_agent_env" ]] && source "$_ssh_agent_env" >/dev/null
if ! _ssh_agent_alive; then
    ssh-agent -s >| "$_ssh_agent_env"
    chmod 600 "$_ssh_agent_env"
    source "$_ssh_agent_env" >/dev/null
fi
unset -f _ssh_agent_alive
unset _ssh_agent_env
