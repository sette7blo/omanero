# Run with: python3 -m unittest tests/test_browser_entries.py
# Runs install.sh and uninstall.sh from a copy of the plugin in a throwaway
# HOME, with stand-ins for the wallet tools and xdg-mime, and checks that only
# this checkout's browser entries are added and removed.
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN_ID = "io.github.sette7blo.omanero"
STUB = "#!/bin/sh\nexit 0\n"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class Installer(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix="omanero-browser-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.project = os.path.join(self.tmp, "checkout", "omanero")
        os.makedirs(self.project)
        for name in ("install.sh", "uninstall.sh", "omanero.desktop.in", "lib", "extension"):
            src = os.path.join(ROOT, name)
            (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, os.path.join(self.project, name))
        # The wallet tool itself is not under test: uninstall only asks it to lock.
        write(os.path.join(self.project, "bin", "omanero"), STUB)
        os.chmod(os.path.join(self.project, "bin", "omanero"), 0o755)
        stubs = os.path.join(self.tmp, "stubs")
        for tool in ("monero-wallet-rpc", "qrencode", "wl-copy"):
            write(os.path.join(stubs, tool), STUB)
            os.chmod(os.path.join(stubs, tool), 0o755)
        # Answers as if the handler had been set.
        write(os.path.join(stubs, "xdg-mime"), '#!/bin/sh\n[ "$1" = query ] && echo omanero.desktop\nexit 0\n')
        os.chmod(os.path.join(stubs, "xdg-mime"), 0o755)
        self.home = os.path.join(self.tmp, "home")
        self.config = os.path.join(self.home, ".config")
        os.makedirs(self.config)
        self.env = {
            "HOME": self.home, "PATH": stubs + ":/usr/bin:/bin", "LANG": "C.UTF-8",
            "XDG_CONFIG_HOME": self.config,
            "XDG_DATA_HOME": os.path.join(self.home, ".local", "share"),
            "XDG_STATE_HOME": os.path.join(self.home, ".local", "state"),
        }
        self.link = os.path.join(self.config, "omarchy", "plugins", PLUGIN_ID)
        self.ext = os.path.join(self.project, "extension", "x")
        self.cli = os.path.join(self.project, "bin", "omanero")

    def run_script(self, name, *args):
        out = subprocess.run([os.path.join(self.project, name), *args], env=self.env,
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        return out.stdout

    def host(self, browser):
        return os.path.join(self.config, browser, "NativeMessagingHosts", PLUGIN_ID + ".json")

    def flags(self, name):
        return os.path.join(self.config, name)

    def test_only_this_checkouts_entries_are_added_and_removed(self):
        for browser in ("BraveSoftware/Brave-Browser", "chromium", "google-chrome", "vivaldi"):
            os.makedirs(os.path.join(self.config, browser))
        # Someone else's registration under the same name.
        foreign = json.dumps({"name": PLUGIN_ID, "path": "/opt/other/bin/thing", "type": "stdio",
                              "allowed_origins": ["chrome-extension://abc/"]})
        write(self.host("google-chrome"), foreign)
        # A registration that is a symlink, even one that names our tool.
        target = os.path.join(self.tmp, "elsewhere.json")
        write(target, json.dumps({"name": PLUGIN_ID, "path": self.cli}))
        os.makedirs(os.path.dirname(self.host("vivaldi")))
        os.symlink(target, self.host("vivaldi"))

        before = {
            # Other extensions first, as Omarchy writes them.
            "brave-flags.conf": "--enable-features=Foo\n--load-extension=/opt/a,/opt/b\n",
            # The folder versions before 0.5 added.
            "chromium-flags.conf": "--load-extension=%s/extension,/opt/c\n" % self.project,
            # No --load-extension line yet.
            "chrome-flags.conf": "--ozone-platform=wayland\n",
            # Added through the plugin link instead of the real folder.
            "google-chrome-flags.conf": "--load-extension=%s/extension/x,/opt/d\n" % self.link,
            # Another plugin whose path merely looks like ours.
            "microsoft-edge-stable-flags.conf": "--load-extension=/opt/other/extension/x,/opt/other/extension\n",
        }
        for name, text in before.items():
            write(self.flags(name), text)
        # A flags file kept in a dotfiles folder and linked into place.
        dotfile = os.path.join(self.tmp, "dotfiles", "brave-beta-flags.conf")
        write(dotfile, "--load-extension=/opt/e\n")
        os.symlink(dotfile, self.flags("brave-beta-flags.conf"))

        self.run_script("install.sh", "--no-enable")

        for browser in ("BraveSoftware/Brave-Browser", "chromium"):
            data = json.loads(read(self.host(browser)))
            self.assertEqual(data["path"], self.cli)
            self.assertEqual(data["allowed_origins"], ["chrome-extension://lkdojiemjmekaibbklkoheninffafick/"])
        self.assertEqual(read(self.host("google-chrome")), foreign)
        self.assertTrue(os.path.islink(self.host("vivaldi")))
        self.assertEqual(json.loads(read(target)), {"name": PLUGIN_ID, "path": self.cli})
        self.assertFalse(os.path.exists(self.host("microsoft-edge")))

        self.assertEqual(read(self.flags("brave-flags.conf")),
                         "--enable-features=Foo\n--load-extension=/opt/a,/opt/b,%s\n" % self.ext)
        self.assertEqual(read(self.flags("chromium-flags.conf")), "--load-extension=%s,/opt/c\n" % self.ext)
        self.assertEqual(read(self.flags("chrome-flags.conf")),
                         "--ozone-platform=wayland\n--load-extension=%s\n" % self.ext)
        self.assertEqual(read(self.flags("google-chrome-flags.conf")), before["google-chrome-flags.conf"])
        self.assertEqual(read(self.flags("microsoft-edge-stable-flags.conf")),
                         "--load-extension=/opt/other/extension/x,/opt/other/extension,%s\n" % self.ext)
        self.assertTrue(os.path.islink(self.flags("brave-beta-flags.conf")))
        self.assertEqual(read(dotfile), "--load-extension=/opt/e,%s\n" % self.ext)

        # Nothing left to do: the on-load run changes nothing, a second full run neither.
        snapshot = {n: read(self.flags(n)) for n in list(before) + ["brave-beta-flags.conf"]}
        self.assertEqual(self.run_script("install.sh", "--if-needed", "--no-enable"), "")
        self.run_script("install.sh", "--no-enable")
        self.assertEqual({n: read(self.flags(n)) for n in snapshot}, snapshot)

        self.run_script("uninstall.sh")

        self.assertFalse(os.path.lexists(self.host("BraveSoftware/Brave-Browser")))
        self.assertFalse(os.path.lexists(self.host("chromium")))
        self.assertEqual(read(self.host("google-chrome")), foreign)
        self.assertTrue(os.path.islink(self.host("vivaldi")))
        self.assertTrue(os.path.exists(target))

        self.assertEqual(read(self.flags("brave-flags.conf")), before["brave-flags.conf"])
        self.assertEqual(read(self.flags("chromium-flags.conf")), "--load-extension=/opt/c\n")
        self.assertEqual(read(self.flags("chrome-flags.conf")), "--ozone-platform=wayland\n")
        self.assertEqual(read(self.flags("google-chrome-flags.conf")), "--load-extension=/opt/d\n")
        self.assertEqual(read(self.flags("microsoft-edge-stable-flags.conf")), before["microsoft-edge-stable-flags.conf"])
        self.assertTrue(os.path.islink(self.flags("brave-beta-flags.conf")))
        self.assertEqual(read(dotfile), "--load-extension=/opt/e\n")

    def test_a_foreign_registration_does_not_make_setup_run_again(self):
        os.makedirs(os.path.join(self.config, "chromium"))
        write(self.host("chromium"), json.dumps({"name": PLUGIN_ID, "path": "/opt/other/bin/thing"}))
        out = self.run_script("install.sh", "--no-enable")
        self.assertIn("belongs to something else", out)
        self.assertEqual(self.run_script("install.sh", "--if-needed", "--no-enable"), "")


if __name__ == "__main__":
    unittest.main()
