// Pure helpers for content.js: finding Monero addresses in page text and
// reading an X handle out of a path. No DOM in here, so it runs under Node
// for tests.

var OmaneroDetect = (function () {
  // A standard address or subaddress, mainnet (4, 8) or stagenet (5, 7), that
  // stands on its own: 95 base58 characters with nothing alphanumeric on
  // either side. Which network is acceptable is the wallet's call.
  var ADDRESS_RE = /(?<![A-Za-z0-9])[4578][1-9AB][1-9A-HJ-NP-Za-km-z]{93}(?![A-Za-z0-9])/g
  var HANDLE_RE = /^[A-Za-z0-9_]{1,15}$/
  var MAX_ITEMS = 5

  // First path segments on x.com that are pages, not people.
  var RESERVED = ["home", "explore", "notifications", "messages", "search", "settings", "compose",
    "i", "login", "logout", "signup", "tos", "privacy", "hashtag", "jobs", "intent", "share"]

  function findAddresses(text) {
    var found = String(text || "").match(ADDRESS_RE) || []
    var out = []
    for (var i = 0; i < found.length; i++) {
      if (out.indexOf(found[i]) === -1) out.push(found[i])
    }
    return out
  }

  function handleFromPath(path) {
    var first = String(path || "").split(/[?#]/)[0].split("/")[1] || ""
    if (!HANDLE_RE.test(first) || RESERVED.indexOf(first.toLowerCase()) !== -1) return ""
    return first
  }

  // One entry per address, bio before posts, capped.
  function unique(items) {
    var out = []
    var sorted = (items || []).slice().sort(function (a, b) {
      return (a.source === "bio" ? 0 : 1) - (b.source === "bio" ? 0 : 1)
    })
    for (var i = 0; i < sorted.length && out.length < MAX_ITEMS; i++) {
      var seen = false
      for (var j = 0; j < out.length; j++) seen = seen || out[j].address === sorted[i].address
      if (!seen) out.push(sorted[i])
    }
    return out
  }

  // ----- People seen with an address in their bio ---------------------------
  // known maps a lowercased handle to { address, at }. It lives in the
  // browser's local storage and is what puts a badge next to a name in the
  // feed, where the bio itself is not on the page.
  var MAX_KNOWN = 2000

  function lookup(known, handle) {
    var entry = handle && known ? known[String(handle).toLowerCase()] : null
    return entry && typeof entry.address === "string" && findAddresses(entry.address).length === 1 ? entry.address : ""
  }

  // Both return true when known changed and needs saving.
  function remember(known, handle, address, now) {
    if (!HANDLE_RE.test(handle) || findAddresses(address).length !== 1) return false
    var key = handle.toLowerCase()
    if (known[key] && known[key].address === address) return false
    known[key] = { address: address, at: now }
    var keys = Object.keys(known)
    if (keys.length > MAX_KNOWN) {
      keys.sort(function (a, b) { return (known[a].at || 0) - (known[b].at || 0) })
      for (var i = 0; i < keys.length - MAX_KNOWN; i++) delete known[keys[i]]
    }
    return true
  }

  function forget(known, handle) {
    var key = String(handle || "").toLowerCase()
    if (!known[key]) return false
    delete known[key]
    return true
  }

  return {
    findAddresses: findAddresses, handleFromPath: handleFromPath, unique: unique,
    lookup: lookup, remember: remember, forget: forget, MAX_KNOWN: MAX_KNOWN
  }
})()

if (typeof module !== "undefined" && module.exports) module.exports = OmaneroDetect
