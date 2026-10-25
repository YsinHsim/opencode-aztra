# opencode-aztra

Connect OpenCode to [Aztra](https://aztra.my) — projects, issues, sprints, time logs, goals
and wiki — as a remote MCP server.

One command, one prompt for your workspace API key. Nothing secret lives in this repo.

## What it does

- Prompts for your Aztra API key and stores it at `~/.config/opencode/aztra.key` (mode `0600`).
- Adds an `aztra` entry to `~/.config/opencode/opencode.json`, referencing the key file rather
  than embedding the token.
- Preserves every other MCP entry and provider setting already in that file.
- Backs the config up before changing it.

## Before you start

1. An Aztra account with access to a workspace.
2. An API key / MCP key from that workspace.
3. OpenCode installed.
4. `python3` available (used only to merge the JSON config safely).

## Install

```bash
git clone https://github.com/YsinHsim/opencode-aztra.git
cd opencode-aztra
./install.sh
```

You will be asked once:

```
Create a key in Aztra: Workspace settings -> API / MCP keys.
Paste it below (input hidden, stored in ~/.config/opencode/aztra.key):
>
```

Restart OpenCode afterwards. The `aztra` tools should appear.

## Non-interactive install

Useful when `opencode-bootstrap` drives the setup, or for a scripted machine.

```bash
cp .env.example .env
chmod 600 .env
# put AZTRA_API_KEY=... in .env
./install.sh --with-token
```

`--with-token` takes the key from the environment or `.env` and never prompts. It fails with a
clear message if no key is available.

## What ends up in your config

```json
{
  "mcp": {
    "aztra": {
      "type": "remote",
      "url": "https://aztra.my/mcp",
      "oauth": false,
      "headers": {
        "Authorization": "{file:~/.config/opencode/aztra.key}",
        "Accept": "application/json, text/event-stream"
      }
    }
  }
}
```

`{file:...}` is OpenCode's file-reference syntax: the secret is read from disk at runtime, so
`opencode.json` itself stays safe to share, sync or commit.

## Configuration

| Setting | Default | Override |
|---|---|---|
| API key file | `~/.config/opencode/aztra.key` | `AZTRA_API_KEY` env var, or `.env` |
| OpenCode config | `~/.config/opencode/opencode.json` | `OPENCODE_CONFIG` |
| Config directory | `~/.config/opencode` | `OPENCODE_CONFIG_DIR` |
| MCP endpoint | `https://aztra.my/mcp` | `AZTRA_URL` |

## Re-running

Safe. An existing key is kept unless you type a new one; the `aztra` config entry is refreshed
to the tested defaults; other MCP entries are untouched.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No key provided` | empty input | re-run and paste the key |
| `Key stored ... (chmod 600)` then tools missing | OpenCode not restarted | restart OpenCode |
| `not valid JSON` | hand-edited config broken | restore the `.bak.*` file printed by the installer |
| Tools listed but calls fail | key revoked or wrong workspace | generate a new key, re-run `./install.sh` |
| `python3 not found` | missing interpreter | `brew install python@3.12` |

## Security

- The key lives only in `~/.config/opencode/aztra.key`, mode `0600`, gitignored.
- `opencode.json` references the file; it does not contain the token.
- Revoke a key from your Aztra workspace settings if it leaks.
- An Aztra key is scoped to its workspace. Treat it like a password: it can read and write
  issues, comments, wiki pages and time logs in that workspace.

## Related repos

Part of a small set of single-purpose OpenCode installers. Install in this order:

1. [`opencode-bootstrap`](https://github.com/YsinHsim/opencode-bootstrap) — OpenCode CLI, provider config, skills
2. [`opencode-aztra`](https://github.com/YsinHsim/opencode-aztra) — company work: tickets, sprints, wiki (this repo)
3. [`opencode-google`](https://github.com/YsinHsim/opencode-google) — Calendar, Gmail, Drive, Docs, Sheets, Tasks, Contacts

Each owns exactly one secret and one config entry, so they can be installed, updated or removed
independently.
