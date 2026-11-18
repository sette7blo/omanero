"""Browser entries of the omanero plugin, shared by install.sh and uninstall.sh.

Two kinds of entries let the X extension reach the wallet tool:
- a native messaging registration, <browser dir>/NativeMessagingHosts/<plugin id>.json
- the extension's folder in the --load-extension list of the browser flags files

Only entries that belong to this checkout are written, kept up to date or
removed. A registration belongs to it when its "path" resolves to this
checkout's bin/omanero; a flags entry when it resolves to this checkout's
extension/x, or to extension/, where versions before 0.5 put it. Anything else
is left exactly as it is.

Usage:
  browser_entries.py status    <config home> <project dir> <plugin id>
  browser_entries.py install   <config home> <project dir> <plugin id> <extension id>
  browser_entries.py uninstall <config home> <project dir> <plugin id>
"""

import json
import os
import sys
import tempfile

BROWSER_DIRS = [
    "BraveSoftware/Brave-Browser",
    "chromium",
    "google-chrome",
    "vivaldi",
    "microsoft-edge",
]
# Same flag files Omarchy uses for its own Chromium extensions.
FLAG_FILES = [
    "chromium-flags.conf",
    "chrome-flags.conf",
    "google-chrome-flags.conf",
    "brave-flags.conf",
    "brave-beta-flags.conf",
    "brave-nightly-flags.conf",
    "brave-origin-flags.conf",
    "brave-origin-beta-flags.conf",
    "microsoft-edge-stable-flags.conf",
]
PREFIX = "--load-extension="


def log(message):
    print("[omanero] " + message, flush=True)


def same(path, target):
    return bool(path) and os.path.realpath(path) == os.path.realpath(target)


def host_file(config, browser, plugin_id):
    return os.path.join(config, browser, "NativeMessagingHosts", plugin_id + ".json")


def host_state(path, cli):
    """absent, ours or foreign. A symlink is never ours: writing to it or
    deleting it would act on whatever it points to."""
    if not os.path.lexists(path):
        return "absent"
    if os.path.islink(path) or not os.path.isfile(path):
        return "foreign"
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return "foreign"
    if isinstance(data, dict) and isinstance(data.get("path"), str) and same(data["path"], cli):
        return "ours"
    return "foreign"


def write_atomic(path, text, mode):
    """Replaces path with text. The temporary file sits next to the target,
    so the rename never crosses a file system."""
    folder = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".omanero.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.lexists(tmp):
            os.unlink(tmp)
        raise


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines(keepends=True)


def write_flags(path, lines):
    # A flags file may be a link into a dotfiles folder: edit the real file.
    real = os.path.realpath(path)
    write_atomic(real, "".join(lines), os.stat(real).st_mode & 0o7777)


def split_line(line):
    """The entries of a --load-extension line, or None for any other line."""
    body = line.rstrip("\r\n")
    if not body.startswith(PREFIX):
        return None
    return body[len(PREFIX):].split(",")


def join_line(entries, line):
    ending = line[len(line.rstrip("\r\n")):] or "\n"
    return PREFIX + ",".join(entries) + ending


def flags_has(path, ext):
    try:
        lines = read_lines(path)
    except OSError:
        return False
    for line in lines:
        entries = split_line(line)
        if entries and any(same(e.strip(), ext) for e in entries):
            return True
    return False


def flags_add(path, ext, legacy):
    """Puts ext in the first --load-extension line, or replaces this
    checkout's legacy entry with it. Returns what changed."""
    lines = read_lines(path)
    if flags_has(path, ext):
        return None
    for i, line in enumerate(lines):
        entries = split_line(line)
        if entries and any(same(e.strip(), legacy) for e in entries):
            lines[i] = join_line([ext if same(e.strip(), legacy) else e for e in entries], line)
            write_flags(path, lines)
            return "extension path updated in " + path
    for i, line in enumerate(lines):
        entries = split_line(line)
        if entries is not None:
            kept = [e for e in entries if e.strip()]
            lines[i] = join_line(kept + [ext], line)
            write_flags(path, lines)
            return "extension added to " + path
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(PREFIX + ext + "\n")
    write_flags(path, lines)
    return "extension added to " + path


def flags_remove(path, ours):
    """Drops the entries that resolve to one of ours, from every
    --load-extension line, and a line left with no entries."""
    lines = read_lines(path)
    out, changed = [], False
    for line in lines:
        entries = split_line(line)
        if entries is None:
            out.append(line)
            continue
        kept = [e for e in entries if not any(same(e.strip(), o) for o in ours)]
        if len(kept) == len(entries):
            out.append(line)
            continue
        changed = True
        if any(e.strip() for e in kept):
            out.append(join_line(kept, line))
    if changed:
        write_flags(path, out)
    return changed


def status(config, project, plugin_id):
    """Exit 0 when nothing is left to do: every browser that is there has a
    registration (ours, or someone else's that we leave), and every flags file
    that is there lists the extension."""
    cli = os.path.join(project, "bin", "omanero")
    ext = os.path.join(project, "extension", "x")
    browsers = [b for b in BROWSER_DIRS if os.path.isdir(os.path.join(config, b))]
    for browser in browsers:
        if host_state(host_file(config, browser, plugin_id), cli) == "absent":
            return 1
    # install() only touches flags files when a browser is there.
    if not browsers:
        return 0
    for name in FLAG_FILES:
        path = os.path.join(config, name)
        if os.path.isfile(path) and not flags_has(path, ext):
            return 1
    return 0


def install(config, project, plugin_id, extension_id):
    cli = os.path.join(project, "bin", "omanero")
    ext = os.path.join(project, "extension", "x")
    legacy = os.path.join(project, "extension")
    found = False
    for browser in BROWSER_DIRS:
        if not os.path.isdir(os.path.join(config, browser)):
            continue
        found = True
        path = host_file(config, browser, plugin_id)
        if host_state(path, cli) == "foreign":
            log("left " + path + " as it is: it belongs to something else")
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        body = json.dumps({
            "name": plugin_id,
            "description": "omanero wallet",
            "path": cli,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://" + extension_id + "/"],
        }, indent=2) + "\n"
        write_atomic(path, body, 0o644)
        log("browser link written for " + browser)
    if not found:
        log("no Chromium-family browser found; tipping from X is not set up")
        return 0
    loaded = False
    for name in FLAG_FILES:
        path = os.path.join(config, name)
        if not os.path.isfile(path):
            continue
        loaded = True
        try:
            change = flags_add(path, ext, legacy)
        except OSError as err:
            log("could not update " + path + ": " + err.strerror)
            continue
        if change:
            log(change)
    if loaded:
        log("restart the browser once and the Tip controls appear on X")
    else:
        log("no browser flags file found, so the Tip controls are not loaded")
    return 0


def uninstall(config, project, plugin_id):
    cli = os.path.join(project, "bin", "omanero")
    ours = [os.path.join(project, "extension", "x"), os.path.join(project, "extension")]
    for browser in BROWSER_DIRS:
        path = host_file(config, browser, plugin_id)
        if host_state(path, cli) == "ours":
            os.unlink(path)
            log("removed the browser link for " + browser)
    for name in FLAG_FILES:
        path = os.path.join(config, name)
        if not os.path.isfile(path):
            continue
        try:
            if flags_remove(path, ours):
                log("extension removed from " + path + "; it is gone after the next browser restart")
        except OSError as err:
            log("could not update " + path + ": " + err.strerror)
    return 0


def main(argv):
    if len(argv) == 4 and argv[0] == "status":
        return status(*argv[1:])
    if len(argv) == 5 and argv[0] == "install":
        return install(*argv[1:])
    if len(argv) == 4 and argv[0] == "uninstall":
        return uninstall(*argv[1:])
    print(__doc__[__doc__.index("Usage:"):].rstrip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
