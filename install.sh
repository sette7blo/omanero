#!/usr/bin/env bash
# Idempotent installer for the omanero Omarchy plugin.
# Links the bar widget, the CLI and the launcher, offers omanero as the
# handler for monero: links, and lets its browser extension reach the wallet. It never creates, opens or moves a wallet.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.sette7blo.omanero"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN_LINK="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/omanero"
DESKTOP_LINK="$DATA_HOME/applications/omanero.desktop"
SCHEME="x-scheme-handler/monero"
# Fixed by the "key" in extension/manifest.json.
EXTENSION_ID="lkdojiemjmekaibbklkoheninffafick"
BROWSER_DIRS=(BraveSoftware/Brave-Browser chromium google-chrome vivaldi microsoft-edge)
# Launcher flag files that Omarchy already uses to load its own extensions.
FLAG_FILES=(brave-flags.conf chromium-flags.conf)

ENABLE=true
TAKE_LINKS=false

usage() {
  cat <<USAGE
Usage: $0 [--no-enable] [--take-links]

--no-enable   link everything but leave the bar widget for you to enable.
--take-links  make omanero the handler for monero: links even if another
              wallet already is. Without it, an existing handler is kept.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-enable) ENABLE=false; shift ;;
    --take-links) TAKE_LINKS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

log() { printf '[omanero] %s\n' "$*"; }

link_path() {
  local source_path="$1"
  local target_path="$2"
  mkdir -p "$(dirname "$target_path")"
  if [[ -L "$target_path" && "$(readlink -f "$target_path")" == "$(readlink -f "$source_path")" ]]; then
    return
  fi
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    mv "$target_path" "$target_path.bak.$TIMESTAMP"
    log "backed up existing $target_path"
  fi
  ln -s "$source_path" "$target_path"
}

check_requirements() {
  command -v python3 >/dev/null 2>&1 || log "python3 not found; the wallet tool needs it: sudo pacman -S python"
  command -v monero-wallet-rpc >/dev/null 2>&1 \
    || log "monero-wallet-rpc not found; install the wallet tools: sudo pacman -S monero"
  command -v qrencode >/dev/null 2>&1 || log "qrencode not found; the Receive QR code needs it: sudo pacman -S qrencode"
}

install_plugin_link() {
  link_path "$PROJECT_DIR" "$PLUGIN_LINK"
  log "linked plugin dir -> $PLUGIN_LINK"
}

install_cli() {
  chmod +x "$PROJECT_DIR/bin/omanero"
  link_path "$PROJECT_DIR/bin/omanero" "$CLI_LINK"
  log "linked CLI -> $CLI_LINK"
}

install_desktop() {
  local rendered="$PROJECT_DIR/omanero.desktop"
  sed "s|@@OMANERO_CLI@@|$CLI_LINK|g" "$PROJECT_DIR/omanero.desktop.in" > "$rendered"
  link_path "$rendered" "$DESKTOP_LINK"
  log "linked .desktop -> $DESKTOP_LINK"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
}

# Clicking "Open in wallet" on a monero: link should land in the panel.
register_links() {
  command -v xdg-mime >/dev/null 2>&1 || { log "xdg-mime not found; monero: links are not registered"; return; }
  local current
  current="$(xdg-mime query default "$SCHEME" 2>/dev/null || true)"
  if [[ -z "$current" || "$current" == "omanero.desktop" ]] || $TAKE_LINKS; then
    xdg-mime default omanero.desktop "$SCHEME"
    log "monero: links open in omanero"
  else
    log "monero: links still open in $current; re-run with --take-links to change that"
  fi
}

# Adds extension/ to the browser's --load-extension line, next to the ones
# Omarchy loads the same way. Takes effect the next time the browser starts.
load_extension() {
  local name file ext="$PROJECT_DIR/extension" loaded=false
  for name in "${FLAG_FILES[@]}"; do
    file="$CONFIG_HOME/$name"
    [[ -f "$file" ]] || continue
    loaded=true
    if grep -qF -- "$ext" "$file"; then
      continue
    elif grep -q '^--load-extension=' "$file"; then
      sed -i --follow-symlinks "0,/^--load-extension=/s|^--load-extension=.*|&,$ext|" "$file"
    else
      printf -- '--load-extension=%s\n' "$ext" >> "$file"
    fi
    log "extension added to $file"
  done
  if $loaded; then
    log "restart the browser once and the Tip controls appear on X"
  else
    log "to tip from X: open your browser's extensions page, turn on Developer mode,"
    log "press Load unpacked and choose $ext"
  fi
}

# Lets the browser extension in extension/ talk to the wallet tool.
register_browsers() {
  local dir found=false
  for dir in "${BROWSER_DIRS[@]}"; do
    [[ -d "$CONFIG_HOME/$dir" ]] || continue
    found=true
    mkdir -p "$CONFIG_HOME/$dir/NativeMessagingHosts"
    cat > "$CONFIG_HOME/$dir/NativeMessagingHosts/$PLUGIN_ID.json" <<JSON
{
  "name": "$PLUGIN_ID",
  "description": "omanero wallet",
  "path": "$PROJECT_DIR/bin/omanero",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
JSON
    log "browser link written for $dir"
  done
  if $found; then
    load_extension
  else
    log "no Chromium-family browser found; tipping from X is not set up"
  fi
}

register_omarchy() {
  if ! command -v omarchy >/dev/null 2>&1; then
    log "omarchy not found on PATH; skipping validate/enable"
    return
  fi
  omarchy plugin validate "$PROJECT_DIR"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  if $ENABLE; then
    omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 || true
  fi
}

main() {
  log "plugin dir: $PROJECT_DIR"
  check_requirements
  install_plugin_link
  install_cli
  install_desktop
  register_links
  register_browsers
  register_omarchy
  log "done. Click the Monero icon on the bar to create or restore a wallet."
}

main "$@"
