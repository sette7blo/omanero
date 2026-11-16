import http.server
import importlib.machinery
import importlib.util
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(os.path.dirname(HERE), "bin", "omanero")
FAKE = os.path.join(HERE, "fake_wallet_rpc.py")

sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("omanero_cli", CLI)
spec = importlib.util.spec_from_loader("omanero_cli", loader)
M = importlib.util.module_from_spec(spec)
loader.exec_module(M)

MAIN = "4" + "A" * 94
STAGE = "5" + "B" * 94
SEED = " ".join(["abbey"] * 25)
DAEMON_HEIGHT = 3000
GENESIS = 1600000000


def load(path):
    with open(path) as handle:
        return json.load(handle)


def dump(data, path):
    with open(path, "w") as handle:
        json.dump(data, handle)


def lines_of(path):
    with open(path) as handle:
        return handle.read().split()


def cmdline(pid):
    try:
        with open("/proc/%d/cmdline" % pid) as handle:
            return handle.read()
    except OSError:
        return ""


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Daemon(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if request["method"] == "get_info":
            result = {"height": DAEMON_HEIGHT}
        else:
            height = request["params"]["height"]
            result = {"block_header": {"height": height, "timestamp": GENESIS + height * 120}}
        data = json.dumps({"result": result}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Pure(unittest.TestCase):
    def test_amounts(self):
        self.assertEqual(M.parse_amount("0.05"), 50000000000)
        self.assertEqual(M.parse_amount("1"), 10 ** 12)
        self.assertEqual(M.parse_amount("0.000000000001"), 1)
        for bad in ("", "0", "0.0", "-1", "1,5", "1e3", ".5", "1.", "0.0000000000001", "abc", "1 2"):
            with self.assertRaises(M.Fail, msg=bad):
                M.parse_amount(bad)
        self.assertEqual(M.format_xmr(50000000000), "0.05")
        self.assertEqual(M.format_xmr(10 ** 12), "1")
        self.assertEqual(M.format_xmr(0), "0")
        self.assertEqual(M.format_xmr(1234567890123), "1.234567890123")

    def test_addresses(self):
        self.assertEqual(M.check_address(" " + MAIN + " ", "mainnet"), MAIN)
        self.assertEqual(M.check_address("8" + "A" * 94, "mainnet"), "8" + "A" * 94)
        self.assertEqual(M.check_address("4" + "A" * 105, "mainnet"), "4" + "A" * 105)
        for bad in (STAGE, MAIN[:-1], MAIN + "A", "4" + "0" * 94, "4" + "l" * 94, ""):
            with self.assertRaises(M.Fail, msg=bad):
                M.check_address(bad, "mainnet")
        self.assertEqual(M.check_address(STAGE, "stagenet"), STAGE)

    def test_links(self):
        got = M.parse_uri("monero:%s?tx_amount=0.1&recipient_name=Ann%%20B&tx_description=<b>hi</b>%%0Athere" % MAIN, "mainnet")
        self.assertEqual(got, {"address": MAIN, "amount": "0.1", "recipient": "Ann B", "description": "<b>hi</b> there"})
        self.assertEqual(M.parse_uri("MONERO://" + MAIN, "mainnet")["amount"], "")
        self.assertEqual(len(M.parse_uri("monero:%s?tx_description=%s" % (MAIN, "x" * 500), "mainnet")["description"]), M.MAX_TEXT)
        for bad in ("bitcoin:" + MAIN, "monero:" + STAGE, "monero:%s?tx_amount=lots" % MAIN,
                    "monero:%s?tx_amount=-1" % MAIN, "monero:", "monero:" + MAIN + "?" + "a=1&" * 30,
                    "monero:" + MAIN + "?x=" + "y" * 2000, "monero:$(reboot)"):
            with self.assertRaises(M.Fail, msg=bad):
                M.parse_uri(bad, "mainnet")

    def test_seeds_and_nodes(self):
        self.assertEqual(M.check_seed("  Abbey " * 25), SEED)
        with self.assertRaisesRegex(M.Fail, "Polyseed"):
            M.check_seed("abbey " * 16)
        with self.assertRaisesRegex(M.Fail, "has 24"):
            M.check_seed("abbey " * 24)
        with self.assertRaises(M.Fail):
            M.check_seed("abbey " * 24 + "4bbey")
        self.assertEqual(M.normalize_node("Node.Example.com", "mainnet"), "node.example.com:18081")
        self.assertEqual(M.normalize_node("https://node.example.com:443/", "mainnet"), "https://node.example.com:443")
        self.assertEqual(M.normalize_node("", "mainnet"), "")
        for bad in ("node example", "node.example.com:99999", "ftp://x:1", "x; rm -rf ~", "-x:1", "a:b"):
            with self.assertRaises(M.Fail, msg=bad):
                M.normalize_node(bad, "mainnet")

    def test_digest_prefers_md5_and_handles_sess(self):
        both = ['Digest qop="auth",algorithm=MD5-sess,realm="r",nonce="n"', 'Digest qop="auth",algorithm=MD5,realm="r",nonce="n"']
        self.assertIn("algorithm=MD5,", M.digest_header(both, "u", "p", "POST", "/json_rpc"))
        self.assertIn("algorithm=MD5-sess,", M.digest_header(both[:1], "u", "p", "POST", "/json_rpc"))
        with self.assertRaises(M.RpcDown):
            M.digest_header(['Basic realm="r"'], "u", "p", "POST", "/json_rpc")


class Wallet(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.daemon = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Daemon)
        threading.Thread(target=cls.daemon.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.daemon.shutdown()
        cls.daemon.server_close()

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="omanero-test-")
        self.env = dict(os.environ)
        self.env.update({
            "XDG_CONFIG_HOME": self.tmp + "/config", "XDG_STATE_HOME": self.tmp + "/state",
            "XDG_DATA_HOME": self.tmp + "/data", "XDG_DATA_DIRS": self.tmp + "/system", "OMANERO_WALLET_RPC": FAKE, "PATH": "/usr/bin:/bin",
            "PYTHONDONTWRITEBYTECODE": "1", "OMANERO_NO_SUMMON": "1",
        })
        self.env.pop("FAKE_DIGEST", None)
        self.state = self.tmp + "/state/omarchy/omanero"
        os.makedirs(self.tmp + "/config/omanero")
        dump({"node": "127.0.0.1:%d" % self.daemon.server_address[1], "rpcPort": free_port()},
             self.tmp + "/config/omanero/config.json")

    def tearDown(self):
        self.run_cli("lock")
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cli(self, *args, data=None, env=None):
        proc = subprocess.run([CLI, "--json", *args], input=(json.dumps(data) + "\n") if data is not None else "",
                              capture_output=True, text=True, timeout=90, env=env or self.env)
        self.assertEqual(proc.stderr, "")
        return json.loads(proc.stdout)

    def create(self):
        return self.run_cli("create", data={"password": "hunter2"})

    def test_create_lock_unlock(self):
        first = self.run_cli("status")
        self.assertTrue(first["installed"])
        self.assertFalse(first["walletExists"])
        self.assertFalse(first["unlocked"])

        made = self.create()
        self.assertTrue(made["ok"])
        self.assertEqual(len(made["seed"].split()), 25)
        self.assertEqual(made["address"], MAIN)
        self.assertEqual(made["restoreHeight"], DAEMON_HEIGHT - 5)

        st = self.run_cli("status")
        self.assertTrue(st["unlocked"] and st["synced"] and st["walletExists"])
        self.assertEqual((st["balance"], st["unlockedBalance"]), ("2.5", "2"))
        self.assertEqual((st["height"], st["daemonHeight"], st["restoreHeight"]), (3000, 3000, 2995))

        again = self.create()
        self.assertFalse(again["ok"])
        self.assertIn("already exists", again["error"])
        self.assertTrue(self.run_cli("status")["unlocked"])

        pid = load(self.state + "/rpc.json")["pid"]
        self.assertTrue(self.run_cli("lock")["ok"])
        self.assertFalse(self.run_cli("status")["unlocked"])
        self.assertEqual(sorted(os.listdir(self.state)), ["lock", "page.json", "request.json", "wallet-rpc.log"])
        self.assertNotIn(FAKE, cmdline(pid))

        wrong = self.run_cli("unlock", data={"password": "nope"})
        self.assertEqual(wrong, {"ok": False, "error": "Wrong password"})
        self.assertFalse(os.path.exists(self.state + "/rpc.json"))
        self.assertTrue(self.run_cli("unlock", data={"password": "hunter2"})["ok"])
        self.assertTrue(self.run_cli("status")["unlocked"])

    def test_secrets_stay_private(self):
        self.create()
        for name in os.listdir(self.state):
            self.assertEqual(os.stat(os.path.join(self.state, name)).st_mode & 0o077, 0, name)
        self.assertEqual(os.stat(self.state).st_mode & 0o777, 0o700)
        session = load(self.state + "/rpc.json")
        args = cmdline(session["pid"])
        self.assertIn(FAKE, args)
        self.assertNotIn(session["password"], args)
        self.assertNotIn("hunter2", args)
        with open(self.state + "/rpc.conf") as handle:
            self.assertIn("rpc-bind-ip=127.0.0.1", handle.read())

    def test_sess_only_login(self):
        env = dict(self.env, FAKE_DIGEST="sess")
        self.assertTrue(self.run_cli("create", data={"password": "pw"}, env=env)["ok"])
        self.assertTrue(self.run_cli("status", env=env)["unlocked"])

    def test_restore(self):
        poly = self.run_cli("restore", data={"seed": "abbey " * 16, "password": "pw", "restoreHeight": "100"})
        self.assertIn("Polyseed", poly["error"])
        bad = self.run_cli("restore", data={"seed": SEED, "password": "pw", "restoreHeight": "soon"})
        self.assertIn("block number or a date", bad["error"])
        self.assertFalse(os.path.exists(self.state + "/rpc.json"))

        # 2020-09-14 00:00 UTC is 1600041600: block 347 at 120 s a block.
        got = self.run_cli("restore", data={"seed": SEED, "password": "pw", "restoreHeight": "2020-09-14"})
        self.assertTrue(got["ok"], got)
        self.assertEqual(got["restoreHeight"], 0)
        self.run_cli("lock")
        shutil.rmtree(self.tmp + "/data")
        late = self.run_cli("restore", data={"seed": SEED, "password": "pw", "restoreHeight": "2020-09-16"})
        self.assertEqual(late.get("restoreHeight"), 1787 - 720, late)
        stored = load(self.tmp + "/data/omanero/mainnet/omanero.keys")
        self.assertEqual(stored["restore_height"], 1067)
        self.assertEqual(self.run_cli("status")["restoreHeight"], 1067)

    def test_send_needs_review_then_relays_exactly_that(self):
        self.assertIn("locked", self.run_cli("preview", data={"address": MAIN, "amount": "0.1"})["error"])
        self.create()
        relayed = self.tmp + "/data/omanero/mainnet/relayed.json"

        self.assertIn("not for mainnet", self.run_cli("preview", data={"address": STAGE, "amount": "0.1"})["error"])
        self.assertIn("dot for decimals", self.run_cli("preview", data={"address": MAIN, "amount": "0,1"})["error"])
        self.assertIn("Not enough spendable", self.run_cli("preview", data={"address": MAIN, "amount": "5"})["error"])
        self.assertIn("Nothing to send", self.run_cli("relay", data={"id": ""})["error"])

        review = self.run_cli("preview", data={"address": MAIN, "amount": "0.25"})
        self.assertEqual((review["amount"], review["fee"], review["total"]), ("0.25", "0.00003", "0.25003"))
        self.assertFalse(os.path.exists(relayed))
        self.assertIn("Nothing to send", self.run_cli("relay", data={"id": "0000"})["error"])
        self.assertFalse(os.path.exists(relayed))

        sent = self.run_cli("relay", data={"id": review["id"]})
        self.assertEqual(sent["txHash"], "ab" * 32)
        lines = lines_of(relayed)
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(bytes.fromhex(lines[0][4:])), [{"amount": 250000000000, "address": MAIN}])
        self.assertIn("Nothing to send", self.run_cli("relay", data={"id": review["id"]})["error"])
        self.assertEqual(len(lines_of(relayed)), 1)

    def test_stale_review_is_refused(self):
        self.create()
        review = self.run_cli("preview", data={"address": MAIN, "amount": "0.25"})
        pending = load(self.state + "/pending.json")
        pending["createdAt"] -= 3600
        dump(pending, self.state + "/pending.json")
        self.assertIn("too old", self.run_cli("relay", data={"id": review["id"]})["error"])
        self.assertFalse(os.path.exists(self.tmp + "/data/omanero/mainnet/relayed.json"))

    def test_history(self):
        self.create()
        rows = self.run_cli("history")["transfers"]
        self.assertEqual([r["kind"] for r in rows], ["pool", "out", "in"])
        self.assertEqual(rows[0]["txid"], "")
        self.assertEqual((rows[1]["amount"], rows[1]["incoming"]), ("0.25", False))
        self.assertEqual((rows[2]["amount"], rows[2]["incoming"]), ("1.5", True))

    def test_qr(self):
        self.assertIn("No wallet address", self.run_cli("qr")["error"])
        self.create()
        self.run_cli("lock")
        stub = self.tmp + "/qrencode"
        with open(stub, "w") as handle:
            handle.write("#!/bin/sh\ncat > '%s/qr-input'\nfor i in $(seq 25); do "
                         "printf '##  ##  ##  ##  ##  ##  ##  ##  ##  ##  ##  ##  ##\\n'; done\n" % self.tmp)
        os.chmod(stub, 0o700)
        got = self.run_cli("qr", env=dict(self.env, OMANERO_QRENCODE=stub))
        self.assertEqual(got["rows"], ["10" * 12 + "1"] * 25)
        self.assertEqual(got["address"], MAIN)
        with open(self.tmp + "/qr-input") as handle:
            self.assertEqual(handle.read(), "monero:" + MAIN)
        missing = self.run_cli("qr", env=dict(self.env, OMANERO_QRENCODE=self.tmp + "/nope"))
        self.assertIn("qrencode is not installed", missing["error"])

    def browser(self, origin=None):
        return subprocess.Popen([CLI, origin or M.EXTENSION_ORIGIN], stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=self.env)

    def tell(self, host, message):
        body = json.dumps(message).encode()
        host.stdin.write(struct.pack("<I", len(body)) + body)
        host.stdin.flush()

    def wait_page(self, count):
        for _ in range(50):
            page = self.run_cli("status")["page"]
            if len(page) == count:
                return page
            time.sleep(0.1)
        self.fail("page never had %d entries" % count)

    def test_browser_page_and_tip(self):
        self.assertEqual(self.run_cli("status")["page"], [])
        host = self.browser()
        try:
            self.tell(host, {"type": "page", "items": [
                {"address": MAIN, "handle": "ann_b", "source": "bio"},
                {"address": STAGE, "handle": "wrong_net", "source": "post"},
                {"address": "<b>", "handle": "x", "source": "post"},
                {"address": "8" + "A" * 94, "handle": "<script>", "source": "elsewhere"}, "junk"]})
            self.assertEqual(self.wait_page(2), [
                {"address": MAIN, "handle": "ann_b", "source": "bio"},
                {"address": "8" + "A" * 94, "handle": "", "source": "post"}])

            self.assertIsNone(self.run_cli("status")["request"])
            self.tell(host, {"type": "tip", "address": STAGE, "handle": "ann_b", "source": "bio"})
            self.tell(host, {"type": "tip", "address": MAIN, "handle": "ann_b", "source": "bio", "amount": "5"})
            self.tell(host, {"type": "nonsense"})
            host.stdin.write(struct.pack("<I", 3) + b"{{{")
            host.stdin.flush()
            for _ in range(50):
                request = self.run_cli("status")["request"]
                if request:
                    break
                time.sleep(0.1)
            self.assertEqual((request["address"], request["amount"], request["recipient"]), (MAIN, "", "@ann_b"))
            self.assertIn("not verified", request["description"])
            self.assertEqual(len(self.run_cli("status")["page"]), 2)
        finally:
            host.stdin.close()
            self.assertEqual(host.wait(timeout=10), 0)
            self.assertEqual(host.stderr.read(), b"")
            host.stderr.close()
        # The browser went away: nothing is tippable any more.
        self.assertEqual(self.run_cli("status")["page"], [])
        self.assertTrue(self.run_cli("dismiss")["ok"])
        self.assertIsNone(self.run_cli("status")["request"])

    def test_browser_other_extension_is_refused(self):
        host = self.browser("chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/")
        self.tell(host, {"type": "page", "items": [{"address": MAIN, "handle": "ann", "source": "bio"}]})
        host.stdin.close()
        self.assertEqual(host.wait(timeout=10), 1)
        host.stderr.close()
        self.assertEqual(self.run_cli("status")["page"], [])

    def test_browser_side_profile_is_refused(self):
        relay = "import subprocess, sys; sys.exit(subprocess.call(sys.argv[1:], stdin=sys.stdin))"
        host = subprocess.Popen([sys.executable, "-c", relay, CLI, M.EXTENSION_ORIGIN, "--user-data-dir=/x"],
                                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, env=self.env)
        self.tell(host, {"type": "page", "items": [{"address": MAIN, "handle": "ann", "source": "bio"}]})
        host.stdin.close()
        self.assertEqual(host.wait(timeout=10), 1)
        self.assertEqual(self.run_cli("status")["page"], [])

    def test_browser_stale_page_is_ignored(self):
        self.run_cli("status")
        dump({"pid": os.getpid(), "items": [{"address": MAIN, "handle": "ann", "source": "bio"}]},
             self.state + "/page.json")
        self.assertEqual(self.run_cli("status")["page"], [])

    def test_plugins_with_a_funding_line(self):
        root = self.tmp + "/config/omarchy/plugins"

        def plugin(folder, manifest):
            os.makedirs(root + "/" + folder)
            with open(root + "/" + folder + "/manifest.json", "w") as handle:
                handle.write(manifest if isinstance(manifest, str) else json.dumps(manifest))

        self.assertEqual(self.run_cli("plugins")["plugins"], [])
        plugin("zeta", {"id": "io.example.zeta", "name": "Zeta\nBar", "author": "<b>Zed</b>",
                        "homepage": "https://github.com/zed/zeta", "funding": {"monero": MAIN}})
        plugin("alpha", {"id": "io.example.alpha", "homepage": "javascript:alert(1)",
                         "funding": {"monero": "8" + "A" * 94, "bitcoin": "bc1"}})
        plugin("stage", {"id": "io.example.stage", "name": "Stage", "funding": {"monero": STAGE}})
        plugin("none", {"id": "io.example.none", "name": "None"})
        plugin("odd", {"id": "io.example.odd", "name": "Odd", "funding": "send money"})
        plugin("badid", {"id": "../x", "name": "Bad", "funding": {"monero": MAIN}})
        plugin("broken", "{not json")
        plugin("list", "[1, 2]")
        plugin(".hidden", {"id": "io.example.hidden", "funding": {"monero": MAIN}})
        os.makedirs(root + "/empty")
        os.symlink(root + "/zeta", root + "/linked")
        got = self.run_cli("plugins")["plugins"]
        self.assertEqual([p["id"] for p in got], ["io.example.alpha", "io.example.zeta"])
        self.assertEqual(got[0], {"id": "io.example.alpha", "name": "io.example.alpha", "author": "",
                                  "homepage": "", "address": "8" + "A" * 94, "kind": "plugin"})
        self.assertEqual(got[1], {"id": "io.example.zeta", "name": "Zeta Bar", "author": "<b>Zed</b>",
                                  "homepage": "https://github.com/zed/zeta", "address": MAIN, "kind": "plugin"})

    def test_several_wallets(self):
        folder = self.tmp + "/data/omanero/mainnet"
        self.create()
        st = self.run_cli("status")
        self.assertEqual((st["wallet"], [w["name"] for w in st["wallets"]]), ("omanero", ["omanero"]))

        for bad in ("Has Space", "../x", "removed", "x" * 25, "-lead"):
            self.assertIn("wallet name", self.run_cli("create", data={"password": "pw2", "name": bad})["error"], bad)
        self.assertIn("already exists", self.run_cli("create", data={"password": "pw2", "name": "omanero"})["error"])
        # A failed attempt leaves the wallet in use alone.
        self.assertEqual(self.run_cli("status")["wallet"], "omanero")

        self.assertTrue(self.run_cli("create", data={"password": "pw2", "name": "Tips"})["ok"])
        st = self.run_cli("status")
        self.assertTrue(st["unlocked"])
        self.assertEqual((st["wallet"], [w["name"] for w in st["wallets"]]), ("tips", ["omanero", "tips"]))
        self.assertEqual(st["wallets"][1]["address"], MAIN)
        self.assertTrue(os.path.exists(folder + "/tips.meta.json"))
        self.assertTrue(os.path.exists(folder + "/meta.json"))

        self.assertIn("no wallet named", self.run_cli("config", "apply", data={"set": {"wallet": "nope"}})["error"])
        moved = self.run_cli("use", "omanero")
        self.assertTrue(moved["locked"])
        st = self.run_cli("status")
        self.assertEqual((st["wallet"], st["unlocked"]), ("omanero", False))
        # Each wallet has its own password.
        self.assertIn("Wrong password", self.run_cli("unlock", data={"password": "pw2"})["error"])
        self.assertTrue(self.run_cli("unlock", data={"password": "hunter2"})["ok"])

        restored = self.run_cli("restore", data={"seed": SEED, "restoreHeight": "100", "password": "pw3", "name": "old"})
        self.assertTrue(restored["ok"])
        self.assertEqual(self.run_cli("wallets")["wallet"], "old")

    def test_remove_wallet_moves_files_aside(self):
        folder = self.tmp + "/data/omanero/mainnet"
        self.create()
        self.run_cli("create", data={"password": "pw2", "name": "tips"})
        self.assertIn("no wallet named", self.run_cli("forget", data={"name": "nope"})["error"])

        gone = self.run_cli("forget", data={"name": "tips"})
        self.assertEqual((gone["removed"], gone["wallet"]), ("tips", "omanero"))
        self.assertEqual(sorted(os.listdir(gone["movedTo"])), ["tips.keys", "tips.meta.json"])
        self.assertTrue(gone["movedTo"].startswith(folder + "/removed/tips-"))
        st = self.run_cli("status")
        self.assertEqual((st["wallet"], st["unlocked"], [w["name"] for w in st["wallets"]]), ("omanero", False, ["omanero"]))
        self.assertTrue(st["walletExists"])

        # The name is free again, and the last wallet can go too.
        self.assertTrue(self.run_cli("create", data={"password": "pw4", "name": "tips"})["ok"])
        self.run_cli("forget", data={"name": "tips"})
        last = self.run_cli("forget", data={})
        self.assertEqual(sorted(os.listdir(last["movedTo"])), ["meta.json", "omanero.keys"])
        st = self.run_cli("status")
        self.assertEqual((st["walletExists"], st["wallets"], st["wallet"]), (False, [], "omanero"))
        self.assertEqual(len(os.listdir(folder + "/removed")), 3)

    def test_apps_with_an_appstream_address(self):
        system = self.tmp + "/system/metainfo"
        os.makedirs(system)
        os.makedirs(self.tmp + "/data/appdata")

        def app(path, body):
            with open(path, "w") as handle:
                handle.write('<?xml version="1.0" encoding="UTF-8"?>\n' + body)

        good = ('<component type="desktop-application"><id>com.example.flea</id>'
                '<name>Flea</name><name xml:lang="de">Floh</name>'
                '<developer id="x"><name>Ann</name></developer>'
                '<url type="homepage">https://github.com/ann/flea</url>'
                '<custom><value key="Other::thing">x</value><value key="Monero::address">%s</value></custom>'
                '</component>' % MAIN)
        app(system + "/com.example.flea.metainfo.xml", good)
        app(self.tmp + "/data/appdata/old.appdata.xml",
            '<component><id>org.example.old</id><developer_name>Bo</developer_name>'
            '<url type="homepage">http://insecure.example</url>'
            '<custom><value key="Monero::address">%s</value></custom></component>' % ("8" + "A" * 94))
        app(system + "/stage.metainfo.xml",
            '<component><id>org.example.stage</id><custom><value key="Monero::address">%s</value></custom></component>' % STAGE)
        app(system + "/plain.metainfo.xml", '<component><id>org.example.plain</id><name>Plain</name></component>')
        app(system + "/broken.metainfo.xml", '<component><id>org.example.broken</id><custom><value key="Monero::address">')
        app(system + "/entity.metainfo.xml",
            '<!DOCTYPE c [<!ENTITY a "%s">]><component><id>org.example.entity</id>'
            '<custom><value key="Monero::address">&a;</value></custom></component>' % MAIN)
        app(system + "/badid.metainfo.xml",
            '<component><id>../x</id><custom><value key="Monero::address">%s</value></custom></component>' % MAIN)
        app(system + "/notes.txt", "Monero::address " + MAIN)

        got = self.run_cli("plugins")["plugins"]
        self.assertEqual([p["id"] for p in got], ["com.example.flea", "org.example.old"])
        self.assertEqual(got[0], {"id": "com.example.flea", "name": "Flea", "author": "Ann",
                                  "homepage": "https://github.com/ann/flea", "address": MAIN, "kind": "app"})
        self.assertEqual(got[1], {"id": "org.example.old", "name": "org.example.old", "author": "Bo",
                                  "homepage": "", "address": "8" + "A" * 94, "kind": "app"})

    def test_link_request(self):
        got = self.run_cli("uri", "monero:%s?tx_amount=0.02&tx_description=thanks" % MAIN)
        self.assertTrue(got["ok"])
        request = self.run_cli("status")["request"]
        self.assertEqual((request["address"], request["amount"], request["description"]), (MAIN, "0.02", "thanks"))
        self.assertEqual(request["id"], got["id"])
        self.assertFalse(self.run_cli("uri", "monero:" + STAGE)["ok"])
        self.assertEqual(self.run_cli("status")["request"]["id"], got["id"])
        # A request file edited by something else is checked again on the way out.
        dump({"id": "x", "address": "<b>", "amount": "1", "at": int(time.time())}, self.state + "/request.json")
        self.assertIsNone(self.run_cli("status")["request"])
        old = self.run_cli("open", "monero:" + MAIN)
        self.assertEqual(self.run_cli("status")["request"]["id"], old["id"])
        dump(dict(load(self.state + "/request.json"), at=int(time.time()) - 3600), self.state + "/request.json")
        self.assertIsNone(self.run_cli("status")["request"])
        self.run_cli("uri", "monero:" + MAIN)
        self.run_cli("dismiss")
        self.assertIsNone(self.run_cli("status")["request"])

    def test_config(self):
        self.create()
        self.assertIn("host:port", self.run_cli("config", "set", "node", "not a node")["error"])
        self.assertTrue(self.run_cli("status")["unlocked"])
        kept = self.run_cli("config", "set", "autoLockMinutes", "5")
        self.assertEqual((kept["config"]["autoLockMinutes"], kept["locked"]), (5, False))
        self.assertTrue(self.run_cli("status")["unlocked"])
        self.run_cli("config", "apply", data={"set": {"autoLockMinutes": 9, "node": "Node.Example.com"}})
        st = self.run_cli("status")
        self.assertEqual((st["autoLockMinutes"], st["node"], st["unlocked"]), (9, "node.example.com:18081", False))
        moved = self.run_cli("config", "set", "network", "stagenet")
        self.assertTrue(moved["locked"])
        st = self.run_cli("status")
        self.assertEqual((st["network"], st["unlocked"], st["walletExists"]), ("stagenet", False, False))
        self.assertEqual(st["node"], "node.monerodevs.org:38089")

    def test_auto_lock(self):
        self.create()
        session = load(self.state + "/session.json")
        session["lastActivity"] = int(time.time()) - 31 * 60
        dump(session, self.state + "/session.json")
        self.assertTrue(self.run_cli("status", "--active")["unlocked"])
        session = load(self.state + "/session.json")
        session["lastActivity"] = int(time.time()) - 31 * 60
        dump(session, self.state + "/session.json")
        self.assertFalse(self.run_cli("status")["unlocked"])
        self.assertFalse(os.path.exists(self.state + "/rpc.json"))

    def test_service_that_will_not_start(self):
        env = dict(self.env, FAKE_REFUSE_START="1")
        got = self.run_cli("create", data={"password": "pw"}, env=env)
        self.assertIn("stopped while starting", got["error"])
        self.assertIn("refusing to start", got["error"])
        self.assertFalse(os.path.exists(self.state + "/rpc.json"))

    def test_no_wallet_is_made_when_the_node_is_silent(self):
        dump({"node": "127.0.0.1:%d" % free_port(), "rpcPort": free_port()}, self.tmp + "/config/omanero/config.json")
        got = self.run_cli("create", data={"password": "pw"})
        self.assertIn("is not answering", got["error"])
        self.assertFalse(os.path.exists(self.tmp + "/data/omanero/mainnet/omanero.keys"))
        self.assertFalse(os.path.exists(self.state + "/rpc.json"))

    def test_not_installed(self):
        env = dict(self.env, OMANERO_WALLET_RPC="/nonexistent/monero-wallet-rpc")
        self.assertFalse(self.run_cli("status", env=env)["installed"])
        self.assertIn("not installed yet", self.run_cli("create", data={"password": "pw"}, env=env)["error"])


if __name__ == "__main__":
    unittest.main()
