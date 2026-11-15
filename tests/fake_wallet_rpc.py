#!/usr/bin/env python3
# Stand-in for monero-wallet-rpc in the tests: same config file, same digest
# login, same JSON-RPC method names, no money.

import hashlib
import http.server
import json
import os
import re
import secrets
import sys
import threading

ADDRESS = {"mainnet": "4" + "A" * 94, "stagenet": "5" + "B" * 94}
SEED = " ".join(["abbey"] * 25)


def md5(text):
    return hashlib.md5(text.encode()).hexdigest()


def read_config(path):
    conf = {}
    with open(path) as handle:
        for line in handle:
            key, _, value = line.strip().partition("=")
            if key:
                conf[key] = value
    return conf


class State:
    conf = {}
    opened = None
    server = None


def wallet_file(name):
    return os.path.join(State.conf["wallet-dir"], name + ".keys")


def network():
    return "stagenet" if State.conf.get("stagenet") else "mainnet"


def fail(code, message):
    return {"error": {"code": code, "message": message}}


def call(method, params):
    if method == "get_version":
        return {"version": 65563}
    if method == "create_wallet":
        with open(wallet_file(params["filename"]), "w") as handle:
            json.dump({"password": params["password"], "seed": SEED, "restore_height": 0}, handle)
        State.opened = params["filename"]
        return {}
    if method == "restore_deterministic_wallet":
        if len(params["seed"].split()) != 25:
            return fail(-1, "Electrum-style word list failed verification")
        with open(wallet_file(params["filename"]), "w") as handle:
            json.dump({"password": params["password"], "seed": params["seed"],
                       "restore_height": params["restore_height"]}, handle)
        State.opened = params["filename"]
        return {"address": ADDRESS[network()], "seed": params["seed"], "info": "", "was_deprecated": False}
    if method == "open_wallet":
        try:
            with open(wallet_file(params["filename"])) as handle:
                stored = json.load(handle)
        except OSError:
            return fail(-1, "Failed to open wallet")
        if stored["password"] != params["password"]:
            return fail(-1, "Failed to open wallet")
        State.opened = params["filename"]
        return {}
    if method == "stop_wallet":
        threading.Thread(target=State.server.shutdown, daemon=True).start()
        return {}
    if State.opened is None:
        return fail(-13, "No wallet file")
    if method == "close_wallet":
        State.opened = None
        return {}
    if method == "get_address":
        return {"address": ADDRESS[network()], "addresses": []}
    if method == "get_balance":
        return {"balance": 2500000000000, "unlocked_balance": 2000000000000}
    if method == "get_height":
        return {"height": int(os.environ.get("FAKE_WALLET_HEIGHT", "3000"))}
    if method == "query_key":
        with open(wallet_file(State.opened)) as handle:
            return {"key": json.load(handle)["seed"]}
    if method == "validate_address":
        address = params["address"]
        ok = bool(re.match(r"^[1-9A-HJ-NP-Za-km-z]{95}$", address)) and address[0] == ADDRESS[network()][0]
        return {"valid": ok, "nettype": network(), "integrated": False, "subaddress": False}
    if method == "transfer":
        if not params.get("do_not_relay") or not params.get("get_tx_metadata"):
            return fail(-4, "test wallet only builds unrelayed transactions")
        amount = sum(d["amount"] for d in params["destinations"])
        if amount + 30000000 > 2000000000000:
            return fail(-17, "not enough unlocked money")
        return {"amount": amount, "fee": 30000000, "tx_hash": "cd" * 32,
                "tx_metadata": "feed" + json.dumps(params["destinations"]).encode().hex()}
    if method == "relay_tx":
        with open(os.path.join(State.conf["wallet-dir"], "relayed.json"), "a") as handle:
            handle.write(params["hex"] + "\n")
        return {"tx_hash": "ab" * 32}
    if method == "get_transfers":
        return {
            "in": [{"txid": "11" * 32, "amount": 1500000000000, "fee": 0, "timestamp": 1700000000, "confirmations": 40}],
            "out": [{"txid": "22" * 32, "amount": 250000000000, "fee": 30000000, "timestamp": 1700005000, "confirmations": 12}],
            "pool": [{"txid": "<b>not hex</b>", "amount": 1, "fee": 0, "timestamp": 1700009000, "confirmations": 0}],
        }
    return fail(-32601, "Method not found")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # Like the real service, a login challenge is only good on the connection
    # it was issued on.
    def setup(self):
        super().setup()
        self.nonce = secrets.token_hex(16)

    def log_message(self, *args):
        pass

    def challenge(self):
        self.send_response(401)
        mode = os.environ.get("FAKE_DIGEST", "both")
        if mode in ("both", "md5"):
            self.send_header("WWW-Authenticate",
                             'Digest qop="auth",algorithm=MD5,realm="monero-rpc",nonce="%s",stale=false' % self.nonce)
        if mode in ("both", "sess"):
            self.send_header("WWW-Authenticate",
                             'Digest qop="auth",algorithm=MD5-sess,realm="monero-rpc",nonce="%s",stale=false' % self.nonce)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Digest "):
            return False
        f = {m.group(1): m.group(2) if m.group(2) is not None else m.group(3)
             for m in re.finditer(r'(\w+)=(?:"([^"]*)"|([^,\s]+))', header[7:])}
        user, _, password = State.conf["rpc-login"].partition(":")
        if f.get("username") != user or f.get("nonce") != self.nonce or f.get("uri") != self.path:
            return False
        ha1 = md5("%s:%s:%s" % (user, f.get("realm", ""), password))
        if f.get("algorithm", "MD5").lower() == "md5-sess":
            ha1 = md5("%s:%s:%s" % (ha1, f["nonce"], f["cnonce"]))
        ha2 = md5("POST:%s" % self.path)
        expected = md5("%s:%s:%s:%s:%s:%s" % (ha1, f["nonce"], f["nc"], f["cnonce"], f["qop"], ha2))
        return f.get("response") == expected

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if not self.authorized():
            return self.challenge()
        request = json.loads(body)
        result = call(request["method"], request.get("params") or {})
        reply = {"jsonrpc": "2.0", "id": request.get("id")}
        reply.update(result if "error" in result else {"result": result})
        data = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    if "--config-file" not in sys.argv or "--non-interactive" not in sys.argv:
        sys.exit("fake wallet rpc: expected --config-file <path> --non-interactive")
    State.conf = read_config(sys.argv[sys.argv.index("--config-file") + 1])
    if os.environ.get("FAKE_REFUSE_START"):
        sys.exit("fake wallet rpc: refusing to start")
    State.server = http.server.ThreadingHTTPServer(
        (State.conf["rpc-bind-ip"], int(State.conf["rpc-bind-port"])), Handler)
    State.server.serve_forever()


if __name__ == "__main__":
    main()
