#!/usr/bin/env bash
# Reverses install.sh: locks the wallet, then removes the symlinks, the link
# handler and the session state. Wallet files are never deleted.

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
if [[ -x "$CLI_LINK" ]]; then
  "$CLI_LINK" lock >/dev/null 2>&1 || log "could not lock the wallet; check for a running monero-wallet-rpc"
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

EXTENSION_DIR=""
[[ -L "$PLUGIN_LINK" ]] && EXTENSION_DIR="$(readlink -f "$PLUGIN_LINK")/extension"

remove_link "$PLUGIN_LINK"
remove_link "$CLI_LINK"
remove_link "$DESKTOP_LINK"

if [[ -f "$MIMEAPPS" ]] && grep -q '^x-scheme-handler/monero=omanero\.desktop;\?$' "$MIMEAPPS"; then
  sed -i '/^x-scheme-handler\/monero=omanero\.desktop;\?$/d' "$MIMEAPPS"
  log "monero: links no longer open in omanero"
fi

for dir in BraveSoftware/Brave-Browser chromium google-chrome vivaldi microsoft-edge; do
  host="$CONFIG_HOME/$dir/NativeMessagingHosts/$PLUGIN_ID.json"
  if [[ -f "$host" ]]; then
    rm -f "$host"
    log "removed the browser link for $dir"
  fi
done

# The project dir is wherever the plugin link pointed; read before it went.
for name in brave-flags.conf chromium-flags.conf; do
  file="$CONFIG_HOME/$name"
  if [[ -n "$EXTENSION_DIR" && -f "$file" ]] && grep -qF -- "$EXTENSION_DIR" "$file"; then
    sed -i --follow-symlinks -e "s|,$EXTENSION_DIR||" -e "s|=$EXTENSION_DIR,|=|" -e "\|^--load-extension=$EXTENSION_DIR\$|d" "$file"
    log "extension removed from $file; it is gone after the next browser restart"
  fi
done

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
