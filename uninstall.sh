#!/usr/bin/env bash
# Reverses install.sh: locks the wallet, then removes the browser entries, the
# symlinks, the link handler and the session state. Only what belongs to this
# checkout is removed. Wallet files are never deleted.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ID="io.github.sette7blo.omanero"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PLUGIN_LINK="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/omanero"
DESKTOP_LINK="$DATA_HOME/applications/omanero.desktop"
STATE_DIR="$STATE_HOME/omarchy/omanero"
WALLET_DIR="$DATA_HOME/omanero"
MIMEAPPS="$CONFIG_HOME/mimeapps.list"

log() { printf '[omanero] %s\n' "$*"; }

# Removes only links that point into this plugin; a command or launcher of the
# same name from somewhere else stays.
remove_link() {
  local path="$1" target
  [[ -L "$path" ]] || return 0
  target="$(readlink -m "$path")"
  [[ "$target" == "$PROJECT_DIR" || "$target" == "$PROJECT_DIR/"* ]] || return 0
  unlink "$path"
  log "removed $path"
}

# Saves the wallet and stops the wallet service before anything is unlinked.
# Always the plugin's own command: ~/.local/bin/omanero may be another program.
if [[ -x "$PROJECT_DIR/bin/omanero" ]]; then
  "$PROJECT_DIR/bin/omanero" lock >/dev/null 2>&1 || log "could not lock the wallet; check for a running monero-wallet-rpc"
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

# Before any link goes, so an entry written through the plugin link still
# resolves to this checkout. Only this checkout's entries are removed.
if command -v python3 >/dev/null 2>&1; then
  python3 -I "$PROJECT_DIR/lib/browser_entries.py" uninstall "$CONFIG_HOME" "$PROJECT_DIR" "$PLUGIN_ID" \
    || log "could not remove the browser entries"
else
  log "python3 not found; the browser entries were left"
fi

# The handler names omanero.desktop; it is ours only if that launcher was.
OWN_DESKTOP=false
[[ -L "$DESKTOP_LINK" && "$(readlink -m "$DESKTOP_LINK")" == "$PROJECT_DIR/"* ]] && OWN_DESKTOP=true

remove_link "$PLUGIN_LINK"
remove_link "$CLI_LINK"
remove_link "$DESKTOP_LINK"

if $OWN_DESKTOP && [[ -f "$MIMEAPPS" ]] && grep -q '^x-scheme-handler/monero=omanero\.desktop;\?$' "$MIMEAPPS"; then
  sed -i '/^x-scheme-handler\/monero=omanero\.desktop;\?$/d' "$MIMEAPPS"
  log "monero: links no longer open in omanero"
fi

if [[ -d "$STATE_DIR" ]]; then
  rm -rf "$STATE_DIR"
  log "removed $STATE_DIR"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if [[ -d "$WALLET_DIR" ]]; then
  log "wallet files were left in $WALLET_DIR"
  log "they hold your money; delete them yourself only once the seed is written down"
fi
log "uninstalled $PLUGIN_ID"
