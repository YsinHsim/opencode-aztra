#!/usr/bin/env bash
# opencode-aztra installer.
#
# Registers the Aztra MCP server in OpenCode's config, prompting for the
# workspace API key and storing it at ~/.config/opencode/aztra.key (mode 0600).
# No key is ever written into this repository.
#
# Safe to re-run: existing config entries are preserved, and re-running only
# replaces the "aztra" key.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
CONFIG_FILE="${OPENCODE_CONFIG:-$CONFIG_DIR/opencode.json}"
# The key lives beside the config file, so an OPENCODE_CONFIG override in a test
# never touches the real ~/.config/opencode/aztra.key.
KEY_FILE="$(dirname "$CONFIG_FILE")/aztra.key"
ENV_FILE="$REPO_DIR/.env"

AZTRA_URL="${AZTRA_URL:-https://aztra.my/mcp}"

# Set --with-token to skip the prompt (used by opencode-bootstrap).
NON_INTERACTIVE=0
[ "${1:-}" = "--with-token" ] && NON_INTERACTIVE=1

info() { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. Python (config merge needs a JSON parser) ----------
PY=""
for candidate in python3 python "python3.12" "python3.11"; do
  if command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c 'import json' >/dev/null 2>&1; then PY="$candidate"; break; fi
  fi
done
[ -n "$PY" ] || fail "python3 not found. Install it first (macOS: brew install python@3.12)."
info "Using $PY"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# ---------- 2. API key ----------
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [ -s "$KEY_FILE" ]; then
  info "Existing key found at $KEY_FILE - keeping it."
  # Only offer a replacement on an interactive terminal. With no TTY (CI, scripted
  # install, bootstrap chaining) `read` gets EOF and `set -e` would abort here.
  if [ "$NON_INTERACTIVE" -eq 0 ] && [ -t 0 ]; then
    echo "Enter a new key to replace it, or press Enter to keep the current one:"
    read -rs -p "> " NEW_KEY || NEW_KEY=""
    echo
    if [ -n "${NEW_KEY:-}" ]; then
      printf '%s' "$NEW_KEY" > "$KEY_FILE"
      info "Key replaced."
    fi
  fi
else
  if [ -n "${AZTRA_API_KEY:-}" ]; then
    printf '%s' "$AZTRA_API_KEY" > "$KEY_FILE"
  else
    [ "$NON_INTERACTIVE" -eq 1 ] && fail "No key available. Set AZTRA_API_KEY or create $ENV_FILE."
    [ -t 0 ] || fail "No terminal available to prompt for a key. Use AZTRA_API_KEY=... ./install.sh --with-token"
    echo
    echo "Create a key in Aztra: Workspace settings -> API / MCP keys."
    echo "Paste it below (input hidden, stored in $KEY_FILE):"
    read -rs -p "> " AZTRA_API_KEY || AZTRA_API_KEY=""
    echo
    [ -n "${AZTRA_API_KEY:-}" ] || fail "No key provided."
    printf '%s' "$AZTRA_API_KEY" > "$KEY_FILE"
  fi
fi
chmod 600 "$KEY_FILE"
info "Key stored at $KEY_FILE (chmod 600)"

KEY_VALUE="$(tr -d '\n\r' < "$KEY_FILE")"
[ -n "$KEY_VALUE" ] || fail "$KEY_FILE is empty."

# ---------- 3. Merge into OpenCode config ----------
if [ -f "$CONFIG_FILE" ]; then
  BACKUP="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP"
  info "Backed up config to $BACKUP"
else
  mkdir -p "$(dirname "$CONFIG_FILE")"
  printf '{}\n' > "$CONFIG_FILE"
  info "Created $CONFIG_FILE"
fi

"$PY" - "$CONFIG_FILE" "$KEY_FILE" "$AZTRA_URL" <<'PYEOF'
import json, sys

config_path, key_path, url = sys.argv[1], sys.argv[2], sys.argv[3]

with open(config_path, encoding="utf-8") as fh:
    try:
        cfg = json.load(fh)
    except json.JSONDecodeError as exc:
        sys.exit(f"[x] {config_path} is not valid JSON: {exc}\n    Fix or remove it, then re-run.")

if not isinstance(cfg, dict):
    sys.exit(f"[x] {config_path} does not contain a JSON object at the top level.")

mcp = cfg.setdefault("mcp", {})
if not isinstance(mcp, dict):
    sys.exit("[x] the 'mcp' key in the config is not an object.")

existing = mcp.get("aztra")
# Keep any extra fields the user added, but always point at the tested defaults.
entry = dict(existing) if isinstance(existing, dict) else {}
entry.setdefault("type", "remote")
entry.setdefault("oauth", False)
entry["url"] = url
# Reference the key file rather than embedding the secret in the config.
entry["headers"] = {
    "Authorization": f"{{file:{key_path}}}",
    "Accept": "application/json, text/event-stream",
}
mcp["aztra"] = entry

with open(config_path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")

others = [k for k in mcp if k != "aztra"]
print(f"[+] Registered 'aztra' -> {url}")
if others:
    print(f"[+] Preserved existing MCP entries: {', '.join(sorted(others))}")
PYEOF

chmod 600 "$CONFIG_FILE" 2>/dev/null || true

# ---------- 4. Done ----------
echo
info "Done."
cat <<NEXT
Next steps:

  1. Restart OpenCode so it reloads the MCP config.
  2. Verify the connection in OpenCode; the 'aztra' tools should be listed.
  3. If it fails, check that the key is valid and not revoked:
       cat $KEY_FILE | head -c 8

To change the key later, just re-run ./install.sh.
NEXT
