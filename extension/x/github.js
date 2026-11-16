// Runs on github.com. On a repository's front page it asks the background
// script for the address the repo publishes in its own manifest.json or
// .github/FUNDING.yml, and reads the README; on a profile it reads the bio and
// the profile README. It puts a Tip control on the page and tells the
// background script what this page holds. No keys, and the only requests are
// the background script's, to the repo already on screen.

(function () {
  var D = OmaneroDetect
  var MARK = "data-omanero-tip"
  var last = null
  var timer = 0
  var observer = null
  // What the background script found for the repo on screen.
  var repoKey = ""
  var repoFound = []
  var repoTries = 0

  function send(message, reply) {
    try { chrome.runtime.sendMessage(message, reply) } catch (e) {}
  }

  function pill(item) {
    return OmaneroPill.make(item, MARK, "Tip XMR", OmaneroPill.PILL_STYLE, function (it) {
      send({ type: "tip", address: it.address, handle: it.handle, source: it.source, site: "github", fork: it.fork })
    })
  }

  function textOf(node) {
    if (!node.querySelector("[" + MARK + "]")) return node.textContent
    var copy = node.cloneNode(true)
    var added = copy.querySelectorAll("[" + MARK + "]")
    for (var i = 0; i < added.length; i++) added[i].remove()
    return copy.textContent
  }

  // One control per spot: replaced only when the address changes.
  function placeAfter(node, item) {
    var next = node.nextElementSibling
    var existing = next && next.hasAttribute(MARK) ? next : null
    if (existing && item && existing.getAttribute(MARK) === item.address) return
    if (existing) existing.remove()
    if (item) node.insertAdjacentElement("afterend", pill(item))
  }

  // The first block in a README or bio that holds the address.
  function blockWith(root, address) {
    var blocks = root.querySelectorAll("p, li, pre, td, blockquote, h1, h2, h3, h4, h5, h6, div.highlight")
    for (var i = 0; i < blocks.length; i++) {
      if (textOf(blocks[i]).indexOf(address) !== -1) return blocks[i]
    }
    return root
  }

  // GitHub keeps some sections twice, one for wide windows and one for narrow
  // ones, and hides whichever does not fit. Every match gets a control, so
  // one shows at any width.
  function headings(test) {
    var out = []
    var all = document.querySelectorAll("h2")
    for (var i = 0; i < all.length; i++) {
      if (test(textOf(all[i]).trim())) out.push(all[i])
    }
    return out
  }

  // Beside the Releases heading, on its line: replaced only when the address changes.
  function placeInside(node, item) {
    var existing = null
    for (var i = 0; i < node.children.length; i++) {
      if (node.children[i].hasAttribute(MARK)) existing = node.children[i]
    }
    if (existing && item && existing.getAttribute(MARK) === item.address) return
    if (existing) existing.remove()
    if (item) {
      node.appendChild(OmaneroPill.make(item, MARK, "Tip XMR",
        "display:inline-block;vertical-align:middle;margin:0 0 0 10px;padding:2px 10px;font-size:12px;line-height:16px",
        function (it) {
          send({ type: "tip", address: it.address, handle: it.handle, source: it.source, site: "github", fork: it.fork })
        }))
    }
  }

  function isFork() {
    var header = document.querySelector("#repository-container-header") || document.querySelector("main")
    return header ? /forked from/i.test(header.textContent) : false
  }

  function readme() {
    return document.querySelector("#readme article.markdown-body")
      || document.querySelector("article.markdown-body")
  }

  // The background script can be starting up, or being replaced after an
  // update, when the question arrives; no answer then means ask again.
  function askRepo(page, name) {
    repoTries++
    send({ type: "repo", owner: page.owner, repo: page.repo }, function (found) {
      void chrome.runtime.lastError
      if (repoKey !== name) return
      if (!Array.isArray(found)) {
        if (repoTries < 4) setTimeout(function () { if (repoKey === name) askRepo(page, name) }, 1500)
        return
      }
      repoFound = found
      schedule()
    })
  }

  function clearPills() {
    var added = document.querySelectorAll("[" + MARK + "]")
    for (var i = 0; i < added.length; i++) added[i].remove()
  }

  function scan() {
    timer = 0
    if (!observer) return
    var page = D.githubPage(location.pathname)
    var items = []
    if (!page) {
      clearPills()
      report([], false)
      return
    }
    var name = D.githubName(page)
    var fork = page.repo ? isFork() : false

    if (page.repo) {
      if (repoKey !== name) {
        repoKey = name
        repoFound = []
        repoTries = 0
        askRepo(page, name)
      }
      var structured = repoFound.length ? repoFound[0] : null
      var item = structured ? { address: structured.address, handle: name, source: structured.source, fork: fork } : null
      // No address in a file: the README's first one takes the same spot.
      var front = item ? null : readme()
      var written = front ? D.findAddresses(textOf(front)) : []
      if (written.length) item = { address: written[0], handle: name, source: "readme", fork: fork }
      // Beside Releases when the repo has them, under About otherwise.
      var releases = headings(function (t) { return /^Releases(\s|\d|$)/.test(t) })
      var abouts = headings(function (t) { return t === "About" })
      var h
      for (h = 0; h < releases.length; h++) placeInside(releases[h], item)
      for (h = 0; h < abouts.length; h++) placeAfter(abouts[h], releases.length ? null : item)
      if (item) items.push(item)
    } else {
      repoKey = ""
      repoFound = []
      var bio = document.querySelector(".user-profile-bio, [data-bio-text]")
      if (bio) {
        var inBio = D.findAddresses(textOf(bio))
        var bioItem = inBio.length ? { address: inBio[0], handle: name, source: "bio", fork: false } : null
        placeAfter(bio, bioItem)
        if (bioItem) items.push(bioItem)
      }
    }

    var body = readme()
    if (body) {
      var inReadme = D.findAddresses(textOf(body))
      // An address already offered beside Releases gets no second control.
      var already = items.length && inReadme.length && items[0].address === inReadme[0]
      var readmeItem = inReadme.length && !already
        ? { address: inReadme[0], handle: name, source: page.repo ? "readme" : "profile", fork: fork } : null
      var spot = readmeItem ? blockWith(body, readmeItem.address) : null
      var old = body.querySelectorAll("[" + MARK + "]")
      for (var i = 0; i < old.length; i++) {
        if (!readmeItem || old[i].previousElementSibling !== spot) old[i].remove()
      }
      if (readmeItem) {
        placeAfter(spot, readmeItem)
        items.push(readmeItem)
      }
    }

    report(D.unique(items).map(function (it) {
      return { address: it.address, handle: it.handle, source: it.source, site: "github", fork: it.fork }
    }), false)
  }

  function report(items, force) {
    var body = JSON.stringify(items)
    if (!force && body === last) return
    last = body
    send({ type: "page", items: items })
  }

  function schedule() {
    if (!timer) timer = setTimeout(scan, 400)
  }

  chrome.runtime.onMessage.addListener(function (message) {
    if (message && message.type === "report") report(JSON.parse(last || "[]"), true)
    if (message && message.type === "off" && observer) {
      observer.disconnect()
      observer = null
      clearTimeout(timer)
      clearPills()
    }
  })

  // GitHub swaps pages without a full load; the observer sees each swap.
  observer = new MutationObserver(schedule)
  observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true })
  schedule()
})()
