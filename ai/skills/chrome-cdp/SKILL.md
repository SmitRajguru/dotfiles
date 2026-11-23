---
name: chrome-cdp
description: Interact with local Chrome browser session (only on explicit user approval after being asked to inspect, debug, or interact with a page open in Chrome)
---

# Chrome CDP

Lightweight Chrome DevTools Protocol CLI. Connects directly via WebSocket — no Puppeteer, works with 100+ tabs, instant connection.

## Prerequisites

- A separate Chrome instance started for the session with its own temporary profile and an unused port (see **Isolated browser**). Do not attach to the user's everyday Chrome profile
- Node.js 22+ (uses built-in WebSocket)
- If your browser's `DevToolsActivePort` is in a non-standard location, set `CDP_PORT_FILE` to its full path

## Isolated browser

The debugging port gives full control of the browser, including every site
the profile is logged in to, to anything that can reach the port. So the
session always uses a separate browser: Google Chrome Canary (a build the
user does not browse with), a new temporary profile and a random unused
port. Chrome 136 and later ignore `--remote-debugging-port` on the default
profile directory, so `--user-data-dir` is required as well.

1. Pick a random port that nothing listens on, on the machine the agent
   runs on:

   ```bash
   port=""; for i in 1 2 3 4 5; do p=$(shuf -i 20000-29999 -n 1); ss -ltn "sport = :$p" | grep -q LISTEN || { port=$p; break; }; done; echo "${port:-no free port found}"
   ```

2. Ask the user to check that the port is free on their machine as well
   (`lsof -nP -iTCP:<port> -sTCP:LISTEN` prints nothing) and to start
   Canary with it, from a terminal (macOS):

   ```bash
   "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" \
     --remote-debugging-port=<port> \
     --user-data-dir="$(mktemp -d /tmp/chrome-cdp.XXXXXX)" \
     --no-first-run --no-default-browser-check
   ```

   Linux has no Canary build; use the Dev build, `google-chrome-unstable`,
   with the same flags.

   Once the browser is up, the user opens
   `chrome://inspect/#remote-debugging` in it and checks that remote
   debugging is on, switching it on if it is off. Show this URL with the
   steps every time.

3. When the agent runs on a remote machine over SSH, the user forwards the
   port from their machine in a separate terminal that stays open. Do not
   edit the user's SSH configuration.

   ```bash
   ssh -N -R <port>:127.0.0.1:<port> <remote-host>
   ```

4. On the agent's machine, write a port file for the session from the
   browser's `/json/version` endpoint:

   ```bash
   mkdir -p ~/.cache/cdp
   curl -s http://127.0.0.1:<port>/json/version \
     | python3 -c 'import json,sys,urllib.parse as u; print(u.urlparse(json.load(sys.stdin)["webSocketDebuggerUrl"]).path)' \
     | { read -r ws; printf '%s\n%s\n' <port> "$ws" > ~/.cache/cdp/port-<port>; }
   ```

   Environment variables do not persist between shell calls, so prefix
   every command: `CDP_PORT_FILE=~/.cache/cdp/port-<port> scripts/cdp.mjs list`.

5. The profile starts with no logins, cookies or extensions. Ask before the
   user logs in to any site in it.

6. When done: `scripts/cdp.mjs stop`, delete `~/.cache/cdp/port-<port>`,
   and ask the user to quit Canary, close the SSH window and delete the
   profile (`rm -rf /tmp/chrome-cdp.*`).

## Commands

All commands use `scripts/cdp.mjs`. The `<target>` is a **unique** targetId prefix from `list`; copy the full prefix shown in the `list` output (for example `6BE827FA`). The CLI rejects ambiguous prefixes.

### List open pages

```bash
scripts/cdp.mjs list
```

### Take a screenshot

```bash
scripts/cdp.mjs shot <target> [file]    # default: screenshot-<target>.png in runtime dir
```

Captures the **viewport only**. Scroll first with `eval` if you need content below the fold. Output includes the page's DPR and coordinate conversion hint (see **Coordinates** below).

### Accessibility tree snapshot

```bash
scripts/cdp.mjs snap <target>
```

### Evaluate JavaScript

```bash
scripts/cdp.mjs eval <target> <expr>
```

> **Watch out:** avoid index-based selection (`querySelectorAll(...)[i]`) across multiple `eval` calls when the DOM can change between them (e.g. after clicking Ignore, card indices shift). Collect all data in one `eval` or use stable selectors.

### Other commands

```bash
scripts/cdp.mjs html    <target> [selector]   # full page or element HTML
scripts/cdp.mjs nav     <target> <url>         # navigate and wait for load
scripts/cdp.mjs net     <target>               # resource timing entries
scripts/cdp.mjs click   <target> <selector>    # click element by CSS selector
scripts/cdp.mjs clickxy <target> <x> <y>       # click at CSS pixel coords
scripts/cdp.mjs type    <target> <text>         # Input.insertText at current focus; works in cross-origin iframes unlike eval
scripts/cdp.mjs loadall <target> <selector> [ms]  # click "load more" until gone (default 1500ms between clicks)
scripts/cdp.mjs evalraw <target> <method> [json]  # raw CDP command passthrough
scripts/cdp.mjs open    [url]                  # open new tab
scripts/cdp.mjs stop    [target]               # stop daemon(s)
```

## Coordinates

`shot` saves an image at native resolution: image pixels = CSS pixels × DPR. CDP Input events (`clickxy` etc.) take **CSS pixels**.

```
CSS px = screenshot image px / DPR
```

`shot` prints the DPR for the current page. Typical Retina (DPR=2): divide screenshot coords by 2.

## Tips

- Prefer `snap --compact` over `html` for page structure.
- Use `type` (not eval) to enter text in cross-origin iframes — `click`/`clickxy` to focus first, then `type`.
- A browser started with `--remote-debugging-port` shows no "Allow debugging" prompt. A background daemon keeps each session alive; daemons exit after 20 minutes of inactivity.
