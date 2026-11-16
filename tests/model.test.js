const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

const MAIN = "4" + "A".repeat(94)
const STAGE = "5" + "B".repeat(94)
const SEED = Array(25).fill("abbey").join(" ")
const NOW = Date.UTC(2026, 10, 15, 12, 0, 0)

function status(patch) {
  return JSON.stringify(Object.assign({
    ok: true, installed: true, network: "mainnet", node: "xmr-node.cakewallet.com:18081", customNode: "",
    nodes: ["xmr-node.cakewallet.com:18081", "node.sethforprivacy.com:443"], autoLockMinutes: 30,
    walletExists: true, restoreHeight: 3400000, unlocked: true, busy: false, synced: true,
    nodeReachable: true, address: MAIN, balance: "2.5", unlockedBalance: "2",
    height: 3409000, daemonHeight: 3409000, request: null,
    wallet: "omanero", wallets: [{ name: "omanero", address: MAIN }]
  }, patch))
}

test("status: a good answer is kept as is", () => {
  const st = M.parseStatus(status({}))
  assert.equal(st.balance, "2.5")
  assert.equal(st.address, MAIN)
  assert.deepEqual(st.nodes, ["xmr-node.cakewallet.com:18081", "node.sethforprivacy.com:443"])
  assert.equal(M.level(st), "ready")
  assert.equal(M.heroMeta(st), "2.5 XMR")
  assert.equal(M.syncLine(st), "Synced")
  assert.equal(M.networkLine(st), "Mainnet via xmr-node.cakewallet.com:18081")
})

test("status: anything unreadable is refused, not guessed", () => {
  assert.equal(M.parseStatus(""), null)
  assert.equal(M.parseStatus("<html>"), null)
  assert.equal(M.parseStatus("[]"), null)
  assert.equal(M.parseStatus(JSON.stringify({ ok: false, error: "x" })), null)
})

test("status: markup and odd values never reach the panel", () => {
  const st = M.parseStatus(status({
    balance: "<b>9</b>", unlockedBalance: 7, address: "<img src=x>", node: "evil host; rm -rf ~",
    nodes: ["<i>", "ok.example:1", 5], height: "many", autoLockMinutes: 99999, network: "<script>",
    request: { id: "<b>", address: MAIN }
  }))
  assert.equal(st.balance, "0")
  assert.equal(st.unlockedBalance, "0")
  assert.equal(st.address, "")
  assert.equal(st.node, "")
  assert.deepEqual(st.nodes, ["ok.example:1"])
  assert.equal(st.height, 0)
  assert.equal(st.autoLockMinutes, 1440)
  assert.equal(st.network, "mainnet")
  assert.equal(st.request, null)
})

test("status: a link request is carried with its text cut down", () => {
  const st = M.parseStatus(status({ request: {
    id: "ab12", address: MAIN, amount: "0.02", recipient: "Ann\nB", description: "<b>" + "x".repeat(500)
  } }))
  assert.equal(st.request.address, MAIN)
  assert.equal(st.request.amount, "0.02")
  assert.equal(st.request.recipient, "Ann B")
  assert.equal(st.request.description.length, 120)
  assert.equal(M.parseStatus(status({ request: { id: "ab12", address: MAIN } })).request.amount, "")
  assert.equal(M.parseStatus(status({ request: { id: "ab12", address: "nope" } })).request, null)
})

test("status: addresses seen on the X page", () => {
  const st = M.parseStatus(status({ page: [
    { address: MAIN, handle: "ann_b", source: "bio" },
    { address: "8" + "C".repeat(94), handle: "<b>", source: "nope" },
    { address: "nope", handle: "x", source: "post" }, null, "x"
  ] }))
  assert.deepEqual(st.page, [
    { address: MAIN, handle: "ann_b", source: "bio" },
    { address: "8" + "C".repeat(94), handle: "", source: "post" }
  ])
  assert.equal(M.tipNames(st.page), "@ann_b, 8CCCCCCC...CCCCCCCC")
  assert.equal(M.tooltip(st), "Monero address on this page: @ann_b, 8CCCCCCC...CCCCCCCC")
  assert.match(M.tipNote(st.page[0]), /the X bio of @ann_b\. Nobody has verified it/)
  assert.match(M.tipNote(st.page[1]), /a post on X\. Nobody/)
  assert.deepEqual(M.parseStatus(status({})).page, [])
  assert.deepEqual(M.parseStatus(status({ page: "x" })).page, [])
  assert.equal(M.parseStatus(status({ page: Array(9).fill({ address: MAIN, handle: "a", source: "bio" }) })).page.length, 5)
  assert.deepEqual(M.emptyStatus().page, [])
})

test("plugins with a funding line", () => {
  const items = M.parsePlugins({ plugins: [
    { id: "io.example.zeta", name: "Zeta", author: "Zed", homepage: "https://github.com/zed/zeta", address: MAIN },
    { id: "io.example.alpha", name: "", author: 5, homepage: "javascript:alert(1)", address: MAIN },
    { id: "../x", name: "Bad", address: MAIN },
    { id: "io.example.noaddr", name: "No", address: "<b>" }, null, "x"
  ] })
  assert.equal(items.length, 2)
  assert.deepEqual(items[0], { id: "io.example.zeta", name: "Zeta", author: "Zed", address: MAIN,
    homepage: "https://github.com/zed/zeta", source: "plugin" })
  assert.equal(items[1].name, "io.example.alpha")
  assert.equal(items[1].homepage, "")
  assert.equal(M.pluginSubtitle(items[0]), "by Zed, github.com/zed/zeta")
  assert.equal(M.pluginSubtitle(items[1]), "by 5, io.example.alpha")
  const apps = M.parsePlugins({ plugins: [{ id: "com.example.flea", name: "Flea", author: "Ann", address: MAIN,
    homepage: "https://github.com/ann/flea", kind: "app" }] })
  assert.equal(apps[0].source, "app")
  assert.match(M.tipNote(apps[0]), /AppStream file of the installed app Flea \(github.com\/ann\/flea\)\. Nobody has verified it/)
  assert.match(M.tipNote(items[0]), /manifest of the installed plugin Zeta \(github.com\/zed\/zeta\)\. Nobody has verified it/)
  assert.deepEqual(M.parsePlugins({}), [])
})

test("several wallets", () => {
  const st = M.parseStatus(status({ wallet: "tips", wallets: [
    { name: "omanero", address: MAIN }, { name: "tips", address: "<b>" }, { name: "Bad Name" }, null
  ] }))
  assert.equal(st.wallet, "tips")
  assert.deepEqual(st.wallets, [{ name: "omanero", address: MAIN }, { name: "tips", address: "" }])
  assert.equal(M.networkLine(st), "tips, Mainnet via xmr-node.cakewallet.com:18081")
  assert.equal(M.parseStatus(status({ wallet: "<b>" })).wallet, "omanero")
  assert.deepEqual(M.parseStatus(status({ wallets: "x" })).wallets, [])
  assert.equal(M.walletNameProblem("", st.wallets), "Give the new wallet a name.")
  assert.match(M.walletNameProblem("My Wallet", st.wallets), /lowercase/)
  assert.match(M.walletNameProblem("removed", st.wallets), /lowercase/)
  assert.equal(M.walletNameProblem(" Tips ", st.wallets), "There is already a wallet with that name.")
  assert.equal(M.walletNameProblem("savings-2", st.wallets), "")
})

test("which wallet, and which network, is on show", () => {
  const one = M.parseStatus(status({}))
  assert.equal(M.heroTitle(one), "Monero")
  assert.equal(M.walletLabel(one), "")
  assert.equal(M.tooltip(one), "Monero wallet: unlocked")
  const two = M.parseStatus(status({ wallet: "tips", wallets: [{ name: "omanero", address: MAIN }, { name: "tips", address: MAIN }] }))
  assert.equal(M.heroTitle(two), "tips")
  assert.equal(M.tooltip(two), "Monero wallet: tips, unlocked")
  assert.equal(M.tooltip(M.parseStatus(status({ wallet: "tips", unlocked: false,
    wallets: [{ name: "omanero" }, { name: "tips" }] }))), "Monero wallet: tips, locked")
  const stage = M.parseStatus(status({ network: "stagenet" }))
  assert.equal(M.heroMeta(stage), "2.5 XMR \u00b7 Stagenet")
  assert.equal(M.heroMeta(M.parseStatus(status({ network: "stagenet", unlocked: false }))), "Locked \u00b7 Stagenet")
  assert.equal(M.tooltip(stage), "Monero wallet (stagenet): unlocked")
  assert.equal(M.heroMeta(one), "2.5 XMR")
  assert.equal(M.heroTitle(M.parseStatus(status({ walletExists: false, unlocked: false, wallets: [] }))), "Monero")
})

test("tab keys", () => {
  assert.deepEqual(["1", "2", "3", "4"].map(M.tabForKey), ["send", "receive", "history", "plugins"])
  for (const k of ["0", "5", "a", "", "1.0", " 1"]) assert.equal(M.tabForKey(k), "", k)
  assert.equal(M.nextTab("send", 1), "receive")
  assert.equal(M.nextTab("plugins", 1), "send")
  assert.equal(M.nextTab("send", -1), "plugins")
  assert.equal(M.nextTab("nope", 1), "receive")
})

test("levels and sync lines", () => {
  const at = patch => M.parseStatus(status(patch))
  assert.equal(M.level(at({ installed: false })), "missing")
  assert.equal(M.level(at({ walletExists: false, unlocked: false })), "setup")
  assert.equal(M.level(at({ unlocked: false })), "locked")
  assert.equal(M.heroMeta(at({ unlocked: false })), "Locked")
  assert.equal(M.syncLine(at({ unlocked: false })), "")
  const behind = at({ synced: false, height: 3408000 })
  assert.equal(M.level(behind), "syncing")
  assert.equal(M.syncLine(behind), "Syncing, 1000 blocks to go")
  assert.equal(M.syncLine(at({ synced: false, height: 3408999 })), "Syncing, 1 block to go")
  assert.equal(M.syncLine(at({ synced: false, nodeReachable: false, daemonHeight: 0 })), "Node unreachable")
  assert.equal(M.syncLine(at({ busy: true })), "Syncing with the network")
  assert.equal(M.syncLine(at({ busy: true, synced: false, height: 3400000 })), "Syncing, about 9000 blocks to go")
  assert.equal(M.syncLine(at({ busy: true, synced: false, height: 0, address: "" })), "Syncing with the network")
  assert.equal(M.tooltip(at({ unlocked: false })), "Monero wallet: locked")
})

test("command results", () => {
  assert.deepEqual(M.parseResult("garbage"), { ok: false, error: "No readable answer from the wallet tool." })
  assert.equal(M.parseResult(JSON.stringify({ ok: false, error: "Wrong password" })).error, "Wrong password")
  assert.equal(M.parseResult(JSON.stringify({ ok: false, error: "x".repeat(900) })).error.length, 300)
  assert.equal(M.parseResult(JSON.stringify({ ok: false })).error, "The wallet tool reported an error.")

  assert.deepEqual(M.parseSeed({ seed: SEED, address: MAIN, restoreHeight: 3409000 }),
    { seed: SEED, address: MAIN, restoreHeight: 3409000 })
  assert.equal(M.parseSeed({ seed: "<b>abbey</b>" }), null)

  const review = M.parseReview({ id: "ab12", address: MAIN, amount: "0.25", fee: "0.00003", total: "0.25003" })
  assert.equal(review.total, "0.25003")
  assert.equal(M.parseReview({ id: "ab12", address: "x" }), null)
  assert.equal(M.parseReview({ id: "$(reboot)", address: MAIN }), null)

  assert.equal(M.parseReceipt({ txHash: "ab".repeat(32), amount: "1", fee: "0.1" }).txHash, "ab".repeat(32))
  assert.equal(M.parseReceipt({ txHash: "<b>" }).txHash, "")
})

test("history rows", () => {
  const transfers = M.parseTransfers({ transfers: [
    { kind: "pool", incoming: true, amount: "0.1", fee: "0", timestamp: NOW / 1000 - 30, confirmations: 0 },
    { kind: "out", incoming: false, amount: "0.25", fee: "0.00003", timestamp: NOW / 1000 - 7200, confirmations: 3 },
    { kind: "in", incoming: true, amount: "1.5", fee: "0", timestamp: NOW / 1000 - 86400 * 3, confirmations: 900 },
    { kind: "<b>", amount: "1" }, null, "x"
  ] })
  assert.equal(transfers.length, 3)
  const rows = M.transferRows(transfers, NOW)
  assert.deepEqual(rows.map(r => r.title), ["+0.1 XMR", "-0.25 XMR", "+1.5 XMR"])
  assert.deepEqual(rows.map(r => r.right), ["Waiting for a block", "3 confirmations", "Confirmed"])
  assert.deepEqual(rows.map(r => r.subtitle), ["just now", "2 hours ago", "3 days ago"])
  assert.deepEqual(M.parseTransfers({}), [])
  assert.equal(M.timeAgo(0, NOW), "")
  assert.equal(M.timeAgo(NOW / 1000 - 86400 * 90, NOW), "2026-08-17")
})

test("qr rows must be a clean square", () => {
  const rows = Array(25).fill("01".repeat(12) + "1")
  assert.deepEqual(M.parseQr({ address: MAIN, rows }), { address: MAIN, rows, size: 25 })
  assert.equal(M.parseQr({ address: "<b>", rows }), null)
  assert.equal(M.parseQr({ address: MAIN, rows: rows.slice(1) }), null)
  assert.equal(M.parseQr({ address: MAIN, rows: rows.map(r => r.replace("0", "x")) }), null)
  assert.equal(M.parseQr({ address: MAIN, rows: Array(3).fill("010") }), null)
  assert.equal(M.parseQr({ address: MAIN }), null)
})

test("addresses are shortened and grouped", () => {
  assert.equal(M.shortAddress(MAIN), "4AAAAAAA...AAAAAAAA")
  assert.equal(M.shortAddress("<b>"), "")
  const grouped = M.groupedAddress(MAIN)
  assert.equal(grouped.split(" ").length, 24)
  assert.equal(grouped.replace(/ /g, ""), MAIN)
  assert.equal(M.groupedAddress("nope"), "")
})

test("form checks", () => {
  assert.equal(M.passwordProblem("", ""), "Choose a password.")
  assert.equal(M.passwordProblem("a", "b"), "The two passwords do not match.")
  assert.equal(M.passwordProblem("a", "a"), "")

  assert.equal(M.seedProblem("  "), "Enter the 25-word seed.")
  assert.match(M.seedProblem(Array(16).fill("abbey").join(" ")), /Polyseed/)
  assert.match(M.seedProblem("one two"), /this one has 2/)
  assert.equal(M.seedProblem("  " + SEED + "\n"), "")

  assert.equal(M.sendProblem("", "1", "mainnet"), "Enter the address to pay.")
  assert.equal(M.sendProblem("hello", "1", "mainnet"), "That is not a Monero address.")
  assert.equal(M.sendProblem(STAGE, "1", "mainnet"), "That address is for another network.")
  assert.equal(M.sendProblem(STAGE, "1", "stagenet"), "")
  assert.equal(M.sendProblem(MAIN, "", "mainnet"), "Enter an amount.")
  for (const bad of ["0", "1,5", "-1", "1e3", "abc", "0.0000000000001"])
    assert.match(M.sendProblem(MAIN, bad, "mainnet"), /dot for decimals/, bad)
  assert.equal(M.sendProblem(" " + MAIN + " ", " 0.05 ", "mainnet"), "")
})
