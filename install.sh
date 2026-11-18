#!/usr/bin/env bash
# Idempotent installer for the omanero Omarchy plugin.
# Installs monero-wallet-rpc when it is missing, links the bar widget, the CLI
# and the launcher, offers omanero as the handler for monero: links, and lets
# its browser extension reach the wallet. It never creates, opens or moves a wallet.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ID="io.github.sette7blo.omanero"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN_LINK="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/omanero"
DESKTOP_LINK="$DATA_HOME/applications/omanero.desktop"
SCHEME="x-scheme-handler/monero"
# Fixed by the "key" in extension/x/manifest.json.
EXTENSION_ID="lkdojiemjmekaibbklkoheninffafick"
BROWSER_DIRS=(BraveSoftware/Brave-Browser chromium google-chrome vivaldi microsoft-edge)
# Same flag files Omarchy uses for its own Chromium extensions.
FLAG_FILES=(
  chromium-flags.conf
  chrome-flags.conf
  google-chrome-flags.conf
  brave-flags.conf
  brave-beta-flags.conf
  brave-nightly-flags.conf
  brave-origin-flags.conf
  brave-origin-beta-flags.conf
  microsoft-edge-stable-flags.conf
)

ENABLE=true
TAKE_LINKS=false
IF_NEEDED=false

usage() {
  cat <<USAGE
Usage: $0 [--no-enable] [--take-links] [--if-needed]

--no-enable   link everything but leave the bar widget for you to enable.
--take-links  make omanero the handler for monero: links even if another
              wallet already is. Without it, an existing handler is kept.
--if-needed   do nothing when the plugin is already set up. The bar service
              runs the installer this way.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-enable) ENABLE=false; shift ;;
    --take-links) TAKE_LINKS=true; shift ;;
    --if-needed) IF_NEEDED=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

log() { printf '[omanero] %s\n' "$*"; }

# Never replaces or moves anything: when the path is already taken by something
# that is not this plugin's link, it is left as it is. The plugin calls its own
# bin/ directly, so it works without the link.
link_path() {
  local source_path="$1"
  local target_path="$2"
  mkdir -p "$(dirname "$target_path")"
  if [[ -L "$target_path" && "$(readlink -f "$target_path")" == "$(readlink -f "$source_path")" ]]; then
    return 0
  fi
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    log "left $target_path as it is: something else is already there"
    return 0
  fi
  ln -s "$source_path" "$target_path"
  log "linked $target_path"
}

# Ours, or taken by something we leave alone: either way nothing to do.
in_place() {
  [[ -e "$1" || -L "$1" ]]
}

# Arch package names for the commands the wallet uses. A copy already on PATH,
# including one placed in ~/.local/bin, counts as installed.
missing_packages() {
  local -a pkgs=()
  command -v monero-wallet-rpc >/dev/null 2>&1 || pkgs+=(monero)
  command -v python3 >/dev/null 2>&1 || pkgs+=(python)
  command -v qrencode >/dev/null 2>&1 || pkgs+=(qrencode)
  command -v wl-copy >/dev/null 2>&1 || pkgs+=(wl-clipboard)
  if (( ${#pkgs[@]} )); then
    printf '%s\n' "${pkgs[@]}"
  fi
}

# sudo needs a terminal. From the shell, open one so the password can be typed.
install_packages() {
  local -a pkgs=()
  mapfile -t pkgs < <(missing_packages)
  (( ${#pkgs[@]} )) || return 0
  if [[ -z ${OMANERO_INSTALL_FOREGROUND:-} && ( ! -t 0 || ! -t 1 ) ]] \
    && command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    local quoted="" arg
    quoted="$(printf '%q' "$0")"
    local -a again=()
    $IF_NEEDED && again+=(--if-needed)
    $ENABLE || again+=(--no-enable)
    $TAKE_LINKS && again+=(--take-links)
    for arg in "${again[@]}"; do
      quoted+=" $(printf '%q' "$arg")"
    done
    omarchy-launch-floating-terminal-with-presentation "OMANERO_INSTALL_FOREGROUND=1 $quoted"
    exit 0
  fi
  log "installing packages: ${pkgs[*]}"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm --needed -- "${pkgs[@]}"
  else
    log "no package installer found"
    exit 1
  fi
  hash -r
  mapfile -t pkgs < <(missing_packages)
  if (( ${#pkgs[@]} )); then
    log "still missing after install: ${pkgs[*]}"
    exit 1
  fi
}

setup_complete() {
  local name file dir current cli
  missing_packages | grep -q . && return 1
  cli="$(readlink -f "$PROJECT_DIR/bin/omanero")"
  in_place "$CLI_LINK" || return 1
  if desktop_path_ok; then
    # A launcher rendered by an older version pointed at ~/.local/bin/omanero.
    render_desktop | cmp -s - "$PROJECT_DIR/omanero.desktop" || return 1
    in_place "$DESKTOP_LINK" || return 1
  fi
  if command -v xdg-mime >/dev/null 2>&1; then
    current="$(xdg-mime query default "$SCHEME" 2>/dev/null || true)"
    [[ -n $current ]] || return 1
  fi
  for dir in "${BROWSER_DIRS[@]}"; do
    [[ -d $CONFIG_HOME/$dir ]] || continue
    file="$CONFIG_HOME/$dir/NativeMessagingHosts/$PLUGIN_ID.json"
    [[ -f $file ]] && grep -qF -- "$cli" "$file" || return 1
  done
  for name in "${FLAG_FILES[@]}"; do
    file="$CONFIG_HOME/$name"
    [[ -f $file ]] || continue
    grep -qF -- "$PROJECT_DIR/extension/x" "$file" || return 1
  done
  return 0
}

install_plugin_link() {
  # omarchy plugin add already cloned this folder into the plugin directory.
  # Linking it onto itself would move the checkout aside.
  if [[ -e $PLUGIN_LINK || -L $PLUGIN_LINK ]] \
    && [[ "$(readlink -f "$PLUGIN_LINK")" == "$PROJECT_DIR" ]]; then
    return
  fi
  link_path "$PROJECT_DIR" "$PLUGIN_LINK"
}

install_cli() {
  chmod +x "$PROJECT_DIR/bin/omanero"
  link_path "$PROJECT_DIR/bin/omanero" "$CLI_LINK"
}

# The launcher runs the plugin's own bin/omanero, never ~/.local/bin/omanero:
# that path may belong to another program the installer left alone. A plugin
# path that would need quoting in an Exec key gets no launcher at all.
desktop_path_ok() {
  [[ "$PROJECT_DIR" =~ ^[A-Za-z0-9._/+-]+$ ]]
}

render_desktop() {
  sed "s|@@OMANERO_CLI@@|$PROJECT_DIR/bin/omanero|g" "$PROJECT_DIR/omanero.desktop.in"
}

install_desktop() {
  local rendered="$PROJECT_DIR/omanero.desktop"
  if ! desktop_path_ok; then
    log "no launcher: the plugin path has characters a launcher cannot hold safely"
    return 0
  fi
  render_desktop > "$rendered"
  link_path "$rendered" "$DESKTOP_LINK"
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

# Adds extension/x to the browser's --load-extension line, next to the ones
# Omarchy loads the same way. The Chrome manifest stays one level below
# extension/ so the marketplace sees a single plugin manifest at the repo root.
# Takes effect the next time the browser starts.
load_extension() {
  local name file ext="$PROJECT_DIR/extension/x" old="$PROJECT_DIR/extension" loaded=false
  for name in "${FLAG_FILES[@]}"; do
    file="$CONFIG_HOME/$name"
    [[ -f "$file" ]] || continue
    loaded=true
    if grep -qF -- "$ext" "$file"; then
      continue
    elif grep -qF -- "$old" "$file"; then
      sed -i --follow-symlinks "s|$old|$ext|g" "$file"
      log "extension path updated in $file"
    elif grep -q '^--load-extension=' "$file"; then
      sed -i --follow-symlinks "0,/^--load-extension=/s|^--load-extension=.*|&,$ext|" "$file"
      log "extension added to $file"
    else
      printf -- '--load-extension=%s\n' "$ext" >> "$file"
      log "extension added to $file"
    fi
  done
  if $loaded; then
    log "restart the browser once and the Tip controls appear on X"
  else
    log "no browser flags file found, so the Tip controls are not loaded"
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

already_enabled() {
  command -v omarchy >/dev/null 2>&1 || return 1
  omarchy plugin list --json 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
try:
    plugins = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
sys.exit(0 if any(p.get("id") == want and p.get("enabled") is True for p in plugins) else 1)
' "$PLUGIN_ID"
}

register_omarchy() {
  if ! command -v omarchy >/dev/null 2>&1; then
    log "omarchy not found on PATH; skipping enable"
    return
  fi
  # Rescanning from inside the running service reloads this installer.
  if ! $IF_NEEDED; then
    omarchy plugin validate "$PROJECT_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  if $ENABLE && ! already_enabled; then
    omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 || true
  fi
}

main() {
  if $IF_NEEDED && setup_complete; then
    exit 0
  fi
  install_packages
  log "plugin dir: $PROJECT_DIR"
  install_plugin_link
  install_cli
  install_desktop
  register_links
  register_browsers
  register_omarchy
  log "done. Click the Monero icon on the bar to create or restore a wallet."
}

main "$@"
