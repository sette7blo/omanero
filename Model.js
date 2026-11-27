// Pure-JS helpers shared by Service.qml, Panel.qml and BarWidget.qml: reading
// what bin/omanero prints and turning it into the strings the panel shows.
// No QML types in here, so the whole file runs under Node for tests.
//
// The wallet logic is not here. It lives in bin/omanero; this file only
// re-checks the shape of its output before anything reaches the UI.

var PLUGIN_ID = "io.github.sette7blo.omanero"
var MAX_TEXT = 120
var MAX_ERROR = 300
var MAX_HISTORY = 50
var MAX_SUBADDRESSES = 50
var MAX_LABEL = 40

var ADDRESS_RE = /^[1-9A-HJ-NP-Za-km-z]{95}$|^[1-9A-HJ-NP-Za-km-z]{106}$/
var AMOUNT_RE = /^\d{1,10}(\.\d{1,12})?$/
var NODE_RE = /^(https?:\/\/)?[A-Za-z0-9.-]{1,253}:\d{1,5}$/
var HEX64_RE = /^[0-9a-f]{64}$/
var ID_RE = /^[0-9a-f]{1,32}$/
var WALLET_NAME_RE = /^[a-z0-9][a-z0-9-]{0,23}$/
var PLUGIN_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
var HOMEPAGE_RE = /^https:\/\/[A-Za-z0-9.-]{1,100}(\/[A-Za-z0-9._~\/-]{0,150})?$/
var HANDLE_RE = /^[A-Za-z0-9_]{1,15}$/
var GITHUB_NAME_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(\/[A-Za-z0-9._-]{1,100})?$/
var GITHUB_SOURCES = ["manifest", "funding", "readme", "bio", "profile"]
var SEED_RE = /^[a-z]+( [a-z]+){24}$/

function text(value, max) {
  if (typeof value !== "string" && typeof value !== "number") return ""
  return String(value).replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, max || MAX_TEXT)
}

function int(value) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? Math.floor(n) : 0
}

function amount(value) {
  var s = typeof value === "string" ? value : ""
  return AMOUNT_RE.test(s) ? s : "0"
}

function address(value) {
  var s = typeof value === "string" ? value : ""
  return ADDRESS_RE.test(s) ? s : ""
}

function node(value) {
  var s = typeof value === "string" ? value : ""
  return NODE_RE.test(s) ? s : ""
}

function parseJson(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return data && typeof data === "object" && !Array.isArray(data) ? data : null
  } catch (e) {
    return null
  }
}

function emptyStatus() {
  return {
    installed: true, network: "mainnet", node: "", customNode: "", nodes: [],
    autoLockMinutes: 30, walletExists: false, restoreHeight: 0,
    unlocked: false, busy: false, synced: false, nodeReachable: true,
    address: "", balance: "0", unlockedBalance: "0", height: 0, daemonHeight: 0,
    request: null, page: [], wallet: "omanero", wallets: [], subaddresses: []
  }
}

function parseRequest(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = typeof raw.id === "string" && ID_RE.test(raw.id) ? raw.id : ""
  var to = address(raw.address)
  if (!id || !to) return null
  return {
    id: id, address: to,
    amount: raw.amount ? amount(raw.amount) : "",
    recipient: text(raw.recipient), description: text(raw.description)
  }
}

// Monero addresses the browser extension sees on the X page in front.
function parsePage(raw) {
  var items = []
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length && items.length < 5; i++) {
    var to = list[i] && typeof list[i] === "object" ? address(list[i].address) : ""
    if (!to) continue
    var raw = list[i]
    if (raw.site === "github") {
      items.push({
        address: to, site: "github", fork: raw.fork === true,
        handle: typeof raw.handle === "string" && GITHUB_NAME_RE.test(raw.handle) ? raw.handle : "",
        source: GITHUB_SOURCES.indexOf(raw.source) !== -1 ? raw.source : "readme"
      })
      continue
    }
    var handle = typeof raw.handle === "string" && HANDLE_RE.test(raw.handle) ? raw.handle : ""
    items.push({ address: to, handle: handle, source: raw.source === "bio" ? "bio" : "post", site: "x" })
  }
  return items
}

function parseWallets(raw) {
  var items = []
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length && items.length < 20; i++) {
    var name = list[i] && typeof list[i].name === "string" && WALLET_NAME_RE.test(list[i].name) ? list[i].name : ""
    if (name) items.push({ name: name, address: address(list[i].address) })
  }
  return items
}

// The wallet's subaddresses, index 1 up; index 0 is the main address.
function parseSubaddresses(raw) {
  var items = []
  var seen = {}
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length && items.length < MAX_SUBADDRESSES; i++) {
    var item = list[i]
    if (!item || typeof item !== "object") continue
    var index = int(item.index)
    var to = address(item.address)
    if (index < 1 || !to || seen[index]) continue
    seen[index] = true
    items.push({ index: index, address: to, label: text(item.label, MAX_LABEL).trim() })
  }
  return items
}

function subaddressName(item) {
  return item.label !== "" ? item.label : "Subaddress " + item.index
}

function subaddressAt(list, index) {
  var items = list || []
  for (var i = 0; i < items.length; i++) {
    if (items[i].index === index) return items[i]
  }
  return null
}

function parseStatus(raw) {
  var data = parseJson(raw)
  if (!data || data.ok !== true) return null
  var nodes = []
  var list = Array.isArray(data.nodes) ? data.nodes : []
  for (var i = 0; i < list.length && nodes.length < 8; i++) {
    if (node(list[i])) nodes.push(list[i])
  }
  return {
    installed: data.installed === true,
    network: data.network === "stagenet" ? "stagenet" : "mainnet",
    node: node(data.node), customNode: node(data.customNode), nodes: nodes,
    autoLockMinutes: Math.min(1440, int(data.autoLockMinutes)),
    walletExists: data.walletExists === true,
    restoreHeight: int(data.restoreHeight),
    unlocked: data.unlocked === true, busy: data.busy === true,
    synced: data.synced === true, nodeReachable: data.nodeReachable !== false,
    address: address(data.address),
    balance: amount(data.balance), unlockedBalance: amount(data.unlockedBalance),
    height: int(data.height), daemonHeight: int(data.daemonHeight),
    request: parseRequest(data.request), page: parsePage(data.page),
    wallet: typeof data.wallet === "string" && WALLET_NAME_RE.test(data.wallet) ? data.wallet : "omanero",
    wallets: parseWallets(data.wallets),
    subaddresses: parseSubaddresses(data.subaddresses)
  }
}

// What a command printed: { ok: true, ...fields } or { ok: false, error }.
function parseResult(raw) {
  var data = parseJson(raw)
  if (!data) return { ok: false, error: "No readable answer from the wallet tool." }
  if (data.ok !== true) return { ok: false, error: text(data.error, MAX_ERROR) || "The wallet tool reported an error." }
  return data
}

function parseSeed(result) {
  var seed = typeof result.seed === "string" && SEED_RE.test(result.seed) ? result.seed : ""
  if (!seed) return null
  return { seed: seed, address: address(result.address), restoreHeight: int(result.restoreHeight) }
}

function parseReview(result) {
  var id = typeof result.id === "string" && ID_RE.test(result.id) ? result.id : ""
  var to = address(result.address)
  if (!id || !to) return null
  return { id: id, address: to, amount: amount(result.amount), fee: amount(result.fee), total: amount(result.total) }
}

function parseReceipt(result) {
  var hash = typeof result.txHash === "string" && HEX64_RE.test(result.txHash) ? result.txHash : ""
  return { txHash: hash, amount: amount(result.amount), fee: amount(result.fee) }
}

function parseTransfers(result) {
  var rows = []
  var list = Array.isArray(result.transfers) ? result.transfers : []
  for (var i = 0; i < list.length && rows.length < MAX_HISTORY; i++) {
    var t = list[i]
    if (!t || typeof t !== "object") continue
    var kind = ["in", "out", "pending", "pool"].indexOf(t.kind) !== -1 ? t.kind : ""
    if (!kind) continue
    rows.push({
      kind: kind, incoming: kind === "in" || kind === "pool",
      amount: amount(t.amount), fee: amount(t.fee),
      timestamp: int(t.timestamp), confirmations: int(t.confirmations),
      subaddress: kind === "in" || kind === "pool" ? int(t.subaddress) : 0
    })
  }
  return rows
}

// A square of 0/1 rows, quiet zone included. Anything else draws nothing
// rather than a code that cannot scan.
function parseQr(result) {
  var rows = Array.isArray(result.rows) ? result.rows : []
  var to = address(result.address)
  if (!to || rows.length < 21 || rows.length > 185) return null
  for (var i = 0; i < rows.length; i++) {
    if (typeof rows[i] !== "string" || rows[i].length !== rows.length || !/^[01]+$/.test(rows[i])) return null
  }
  return { address: to, rows: rows, size: rows.length }
}

// Installed plugins whose manifest names a Monero address for their author.
function parsePlugins(result) {
  var items = []
  var list = Array.isArray(result.plugins) ? result.plugins : []
  for (var i = 0; i < list.length && items.length < 100; i++) {
    var p = list[i]
    var to = p && typeof p === "object" ? address(p.address) : ""
    var id = to && typeof p.id === "string" && PLUGIN_ID_RE.test(p.id) ? p.id : ""
    if (!id) continue
    var homepage = typeof p.homepage === "string" && HOMEPAGE_RE.test(p.homepage) ? p.homepage : ""
    items.push({
      id: id, name: text(p.name) || id, author: text(p.author), address: to,
      homepage: homepage, source: p.kind === "app" ? "app" : "plugin"
    })
  }
  return items
}

function pluginSubtitle(item) {
  var where = item.homepage ? item.homepage.replace(/^https:\/\//, "") : item.id
  return item.author ? "by " + item.author + ", " + where : where
}

// ----- Display ------------------------------------------------------------

function shortAddress(value) {
  var s = address(value)
  return s ? s.slice(0, 8) + "..." + s.slice(-8) : ""
}

// An address in groups of four reads back against the source far more
// reliably than one unbroken line.
function groupedAddress(value) {
  var s = address(value)
  return s ? s.replace(/(.{4})/g, "$1 ").replace(/ $/, "") : ""
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

function syncLine(st) {
  if (!st || !st.unlocked) return ""
  var left = st.daemonHeight - st.height
  // While it scans, the wallet answers only now and then; the counts are the
  // last ones it gave.
  if (st.busy) return left > 1 && st.height > 0 ? "Syncing, about " + plural(left, "block", "blocks") + " to go" : "Syncing with the network"
  if (!st.nodeReachable) return "Node unreachable"
  if (st.synced) return "Synced"
  return left > 0 ? "Syncing, " + plural(left, "block", "blocks") + " to go" : "Syncing"
}

// missing | setup | locked | syncing | ready
function level(st) {
  if (!st) return "locked"
  if (!st.installed) return "missing"
  if (!st.walletExists) return "setup"
  if (!st.unlocked) return "locked"
  return st.synced && !st.busy ? "ready" : "syncing"
}

function tipName(item) {
  if (!item.handle) return shortAddress(item.address)
  return item.site === "github" ? item.handle : "@" + item.handle
}

function tipNames(items) {
  var names = []
  for (var i = 0; i < (items || []).length; i++) names.push(tipName(items[i]))
  return names.join(", ")
}

// A page can show any address under any name, so the wording never claims
// more than where the address was seen.
function tipNote(item) {
  if (item.source === "app") {
    return "This address is from the AppStream file of the installed app " + item.name
      + (item.homepage ? " (" + item.homepage.replace(/^https:\/\//, "") + ")" : "")
      + ". Nobody has verified it; a modified package can carry someone else's address."
  }
  if (item.source === "plugin") {
    return "This address is from the manifest of the installed plugin " + item.name
      + (item.homepage ? " (" + item.homepage.replace(/^https:\/\//, "") + ")" : "")
      + ". Nobody has verified it; a copy of a plugin can carry someone else's address."
  }
  if (item.site === "github") {
    var places = { manifest: "the manifest.json", funding: "the FUNDING.yml", readme: "the README",
      bio: "the GitHub bio", profile: "the profile README" }
    return "This address is from " + places[item.source] + " of " + (item.handle || "this GitHub page")
      + (item.fork ? ", which is a fork: its address can differ from the original's" : "")
      + ". Nobody has verified it; check it before sending."
  }
  var where = item.source === "bio" ? "the X bio" : "a post on X"
  return "This address was found in " + where + (item.handle ? " of @" + item.handle : "")
    + ". Nobody has verified it; check it before sending."
}

// The wallet's name matters only once there is more than one.
function walletLabel(st) {
  return st && st.walletExists && st.wallets.length > 1 ? st.wallet : ""
}

function heroTitle(st) {
  return walletLabel(st) || "Monero"
}

function tooltip(st) {
  if (st && st.page.length > 0) return "Monero address on this page: " + tipNames(st.page)
  var lv = level(st)
  var head = "Monero wallet" + (st && st.network === "stagenet" ? " (stagenet)" : "") + ": "
    + (walletLabel(st) ? walletLabel(st) + ", " : "")
  if (lv === "missing") return "Monero wallet: wallet tools not installed"
  if (lv === "setup") return head + "not set up"
  if (lv === "locked") return head + "locked"
  if (lv === "syncing") return head + "syncing"
  return head + "unlocked"
}

// Stagenet is play money; it is named wherever the balance is, never mainnet.
function heroMeta(st) {
  var lv = level(st)
  var net = st && st.network === "stagenet" ? " \u00b7 Stagenet" : ""
  if (lv === "missing") return "Not installed"
  if (lv === "setup") return "No wallet yet" + net
  if (lv === "locked") return "Locked" + net
  return st.balance + " XMR" + net
}

// Number keys pick a tab; anything else is not a tab key.
var TABS = ["send", "receive", "history", "plugins"]

function tabForKey(text) {
  var n = parseInt(text, 10)
  return String(n) === text && n >= 1 && n <= TABS.length ? TABS[n - 1] : ""
}

function nextTab(tab, step) {
  var i = TABS.indexOf(tab)
  if (i === -1) i = 0
  return TABS[(i + step + TABS.length) % TABS.length]
}

function networkLine(st) {
  if (!st) return ""
  // The wallet's name only matters once there is more than one.
  return (st.wallets.length > 1 ? st.wallet + ", " : "")
    + (st.network === "stagenet" ? "Stagenet" : "Mainnet") + (st.node ? " via " + st.node : "")
}

function walletNameProblem(name, wallets) {
  var n = String(name || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (n === "") return "Give the new wallet a name."
  if (!WALLET_NAME_RE.test(n) || n === "removed") return "Use 1 to 24 lowercase letters, digits or dashes for the name."
  for (var i = 0; i < (wallets || []).length; i++) {
    if (wallets[i].name === n) return "There is already a wallet with that name."
  }
  return ""
}

function passwordProblem(first, second) {
  if (String(first || "") === "") return "Choose a password."
  if (first !== second) return "The two passwords do not match."
  return ""
}

function seedProblem(seed) {
  var words = String(seed || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
  if (words.length === 1 && words[0] === "") return "Enter the 25-word seed."
  if (words.length === 16) return "This is a 16-word Polyseed. Only 25-word seeds can be restored for now."
  if (words.length !== 25) return "A Monero seed has 25 words; this one has " + words.length + "."
  return ""
}

function sendProblem(to, value, network) {
  var a = String(to || "").replace(/\s+/g, "")
  if (a === "") return "Enter the address to pay."
  if (!ADDRESS_RE.test(a)) return "That is not a Monero address."
  var prefixes = network === "stagenet" ? "57" : "48"
  if (prefixes.indexOf(a.charAt(0)) === -1) return "That address is for another network."
  var v = String(value || "").replace(/\s+/g, "")
  if (v === "") return "Enter an amount."
  if (!/^\d{1,9}(\.\d{1,12})?$/.test(v) || Number(v) <= 0) return "Write the amount with a dot for decimals, for example 0.05."
  return ""
}

function timeAgo(seconds, nowMs) {
  if (!(seconds > 0)) return ""
  var diff = Math.floor(nowMs / 1000) - seconds
  if (diff < 60) return "just now"
  if (diff < 3600) return plural(Math.floor(diff / 60), "minute", "minutes") + " ago"
  if (diff < 86400) return plural(Math.floor(diff / 3600), "hour", "hours") + " ago"
  if (diff < 86400 * 60) return plural(Math.floor(diff / 86400), "day", "days") + " ago"
  return new Date(seconds * 1000).toISOString().slice(0, 10)
}

// An incoming payment to a subaddress says which one, by label when it has one.
function transferRows(transfers, nowMs, subaddresses) {
  var rows = []
  var list = transfers || []
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    var waiting = t.kind === "pending" || t.kind === "pool"
    var when = timeAgo(t.timestamp, nowMs)
    var to = ""
    if (t.incoming && t.subaddress > 0) {
      var sub = subaddressAt(subaddresses, t.subaddress)
      to = "To " + (sub ? subaddressName(sub) : "subaddress " + t.subaddress)
    }
    rows.push({
      title: (t.incoming ? "+" : "-") + t.amount + " XMR",
      subtitle: to !== "" && when !== "" ? to + ", " + when : (to || when),
      right: waiting ? "Waiting for a block"
        : (t.confirmations < 10 ? plural(t.confirmations, "confirmation", "confirmations") : "Confirmed"),
      incoming: t.incoming, waiting: waiting
    })
  }
  return rows
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID, emptyStatus: emptyStatus, parseStatus: parseStatus, parseResult: parseResult,
    parseSeed: parseSeed, parseReview: parseReview, parseReceipt: parseReceipt,
    parseTransfers: parseTransfers, parseQr: parseQr, parsePage: parsePage, parsePlugins: parsePlugins,
    pluginSubtitle: pluginSubtitle,
    tipName: tipName, tipNames: tipNames, tipNote: tipNote, shortAddress: shortAddress, groupedAddress: groupedAddress,
    syncLine: syncLine, level: level, tooltip: tooltip, heroMeta: heroMeta, networkLine: networkLine, walletLabel: walletLabel, heroTitle: heroTitle,
    tabForKey: tabForKey, nextTab: nextTab, walletNameProblem: walletNameProblem,
    passwordProblem: passwordProblem, seedProblem: seedProblem, sendProblem: sendProblem,
    timeAgo: timeAgo, transferRows: transferRows,
    parseSubaddresses: parseSubaddresses, subaddressName: subaddressName, subaddressAt: subaddressAt
  }
}
