// Pure helpers for the content scripts and the background script: finding
// Monero addresses in page text, reading an X handle or a GitHub owner and
// repo out of a path, and reading the address a repo publishes in its
// manifest.json or FUNDING.yml. No DOM in here, so it runs under Node for tests.

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

  // GitHub: the first path segment is an owner unless it is one of GitHub's
  // own pages; a second one is a repo.
  var GH_OWNER_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/
  var GH_REPO_RE = /^[A-Za-z0-9._-]{1,100}$/
  var GH_RESERVED = ["about", "account", "apps", "codespaces", "collections", "contact", "customer-stories",
    "dashboard", "enterprise", "events", "explore", "features", "github-copilot", "issues", "login", "logout",
    "marketplace", "new", "notifications", "orgs", "organizations", "pricing", "pulls", "readme", "search",
    "security", "settings", "signup", "site", "sponsors", "stars", "team", "topics", "trending", "users"]

  // { owner, repo } for a profile ("" repo) or the front of a repository,
  // null for anything else.
  function githubPage(path) {
    var parts = String(path || "").split(/[?#]/)[0].split("/").filter(function (p) { return p !== "" })
    var owner = parts[0] || ""
    if (!GH_OWNER_RE.test(owner) || GH_RESERVED.indexOf(owner.toLowerCase()) !== -1) return null
    if (parts.length === 1) return { owner: owner, repo: "" }
    var repo = parts[1]
    if (!GH_REPO_RE.test(repo) || repo === "." || repo === "..") return null
    // The repo's front page, or a branch's: that is where the README shows.
    if (parts.length === 2 || (parts[2] === "tree" && parts.length <= 4)) return { owner: owner, repo: repo }
    return null
  }

  function githubName(page) {
    return page ? page.owner + (page.repo ? "/" + page.repo : "") : ""
  }

  // manifest.json: "funding": { "monero": "<address>" }, exactly one address.
  function manifestAddress(text) {
    var data
    try { data = JSON.parse(String(text || "")) } catch (e) { return "" }
    var value = data && data.funding && typeof data.funding.monero === "string" ? data.funding.monero.trim() : ""
    var found = findAddresses(value)
    return found.length === 1 && found[0] === value ? value : ""
  }

  // FUNDING.yml has no Monero platform; a custom entry can hold a monero: link.
  function fundingAddress(text) {
    var found = String(text || "").match(/monero:(?:\/\/)?([4578][1-9AB][1-9A-HJ-NP-Za-km-z]{93})(?![A-Za-z0-9])/)
    return found ? found[1] : ""
  }

  // Structured places first, then what someone wrote about themselves, then
  // anything else on the page.
  var RANK = { manifest: 0, funding: 1, bio: 2, profile: 2, readme: 3, post: 4 }

  // One entry per address, best source first, capped.
  function unique(items) {
    var out = []
    var sorted = (items || []).slice().sort(function (a, b) {
      return (RANK[a.source] === undefined ? 9 : RANK[a.source]) - (RANK[b.source] === undefined ? 9 : RANK[b.source])
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
    githubPage: githubPage, githubName: githubName, manifestAddress: manifestAddress, fundingAddress: fundingAddress,
    lookup: lookup, remember: remember, forget: forget, MAX_KNOWN: MAX_KNOWN
  }
})()

if (typeof module !== "undefined" && module.exports) module.exports = OmaneroDetect
