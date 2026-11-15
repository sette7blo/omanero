// Runs on x.com. Looks for Monero addresses in profile bios and in posts, puts
// a Tip control after each one and an XMR badge next to the names of people
// whose bio was seen to carry one, and tells the background script what this
// page holds. It reads the page and nothing else: no requests, no keys.

(function () {
  var D = OmaneroDetect
  var MARK = "data-omanero-tip"
  var BADGE = "data-omanero-badge"
  var STORE = "known"
  var known = {}
  var dirty = false
  var last = null
  var timer = 0
  var observer = null

  function send(message) {
    // Throws once the extension has been reloaded under a page that is still open.
    try { chrome.runtime.sendMessage(message) } catch (e) {}
  }

  function control(item, attribute, label, style) {
    var button = document.createElement("button")
    button.type = "button"
    button.setAttribute(attribute, item.address)
    button.textContent = label
    button.title = "Tip with the omanero wallet"
    // One fixed look, Monero orange with white text, so the control reads the
    // same on a bio, in a post and inside a name link, in X's light and dark
    // themes alike. Nothing is inherited from where it lands.
    button.style.cssText = "border:0;border-radius:9999px;background:#f26822;color:#fff;"
      + "-webkit-text-fill-color:#fff;font:inherit;font-weight:700;letter-spacing:normal;"
      + "text-transform:none;text-decoration:none;white-space:nowrap;cursor:pointer;flex:none;" + style
    button.addEventListener("click", function (event) {
      // Posts and names are links; the press must not also follow them.
      event.preventDefault()
      event.stopPropagation()
      send({ type: "tip", address: item.address, handle: item.handle, source: item.source })
    })
    return button
  }

  // What the page wrote, without anything this script added to it.
  function textOf(node) {
    if (!node.querySelector("[" + MARK + "],[" + BADGE + "]")) return node.textContent
    var copy = node.cloneNode(true)
    var added = copy.querySelectorAll("[" + MARK + "],[" + BADGE + "]")
    for (var i = 0; i < added.length; i++) added[i].remove()
    return copy.textContent
  }

  // The pill sits after the text block, not inside it, so X redrawing the
  // text does not fight with it.
  function placePill(node, item) {
    var next = node.nextElementSibling
    var existing = next && next.hasAttribute(MARK) ? next : null
    if (existing && item && existing.getAttribute(MARK) === item.address) return
    if (existing) existing.remove()
    if (item) {
      node.insertAdjacentElement("afterend", control(item, MARK, "Tip XMR",
        "display:inline-block;margin:6px 0 0;padding:3px 12px;font-size:13px;line-height:18px"))
    }
  }

  function placeBadge(node, item) {
    var existing = null
    for (var i = 0; i < node.children.length; i++) {
      if (node.children[i].hasAttribute(BADGE)) existing = node.children[i]
    }
    if (existing && item && existing.getAttribute(BADGE) === item.address) return
    if (existing) existing.remove()
    if (item) {
      node.appendChild(control(item, BADGE, "XMR",
        "align-self:center;margin:0 0 0 6px;padding:1px 7px;font-size:11px;line-height:15px"))
    }
  }

  function learn(handle, text) {
    if (!handle) return
    var found = D.findAddresses(text)
    if (found.length) dirty = D.remember(known, handle, found[0], Date.now()) || dirty
    else dirty = D.forget(known, handle) || dirty
  }

  function linkHandle(scope) {
    var link = scope.querySelector('a[href^="/"]')
    return link ? D.handleFromPath(link.getAttribute("href")) : ""
  }

  function badge(nameNode, handle, items) {
    var address = D.lookup(known, handle)
    var item = address ? { address: address, handle: handle, source: "bio" } : null
    placeBadge(nameNode, item)
    if (item) items.push(item)
  }

  function scan() {
    timer = 0
    if (!observer) return
    var items = []
    var i

    // Bios: the profile in front, hover cards, and the rows of a followers or
    // following list. Only a bio teaches whose address it is; a post does not.
    var bios = document.querySelectorAll('[data-testid="UserDescription"]')
    for (i = 0; i < bios.length; i++) {
      var card = bios[i].closest('[data-testid="HoverCard"]')
      var owner = card ? linkHandle(card) : D.handleFromPath(location.pathname)
      learn(owner, textOf(bios[i]))
      if (card) continue
      var found = D.findAddresses(textOf(bios[i]))
      var bioItem = found.length ? { address: found[0], handle: owner, source: "bio" } : null
      placePill(bios[i], bioItem)
      if (bioItem) items.push(bioItem)
    }
    var cells = document.querySelectorAll('[data-testid="UserCell"]')
    for (i = 0; i < cells.length; i++) {
      var who = linkHandle(cells[i])
      // A row with no bio text says nothing either way, so it only ever adds.
      if (who && D.findAddresses(textOf(cells[i])).length) learn(who, textOf(cells[i]))
    }

    var posts = document.querySelectorAll('article[data-testid="tweet"]')
    for (i = 0; i < posts.length; i++) {
      var text = posts[i].querySelector('[data-testid="tweetText"]')
      var name = posts[i].querySelector('[data-testid="User-Name"]')
      var author = name ? linkHandle(name) : ""
      if (text) {
        var inPost = D.findAddresses(textOf(text))
        var postItem = inPost.length ? { address: inPost[0], handle: author, source: "post" } : null
        placePill(text, postItem)
        if (postItem) items.push(postItem)
      }
      if (name) badge(name, author, items)
    }
    for (i = 0; i < cells.length; i++) {
      var row = cells[i].querySelector('a[href^="/"] div[dir]')
      if (row && row.parentElement) badge(row.parentElement, linkHandle(cells[i]), items)
    }

    if (dirty) {
      dirty = false
      var save = {}
      save[STORE] = known
      try { chrome.storage.local.set(save) } catch (e) {}
    }
    report(D.unique(items), false)
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
    // The background script asks again when this tab comes to the front.
    if (message && message.type === "report") report(JSON.parse(last || "[]"), true)
    // No wallet behind this browser profile: a control would do nothing.
    if (message && message.type === "off" && observer) {
      observer.disconnect()
      observer = null
      clearTimeout(timer)
      var added = document.querySelectorAll("[" + MARK + "],[" + BADGE + "]")
      for (var i = 0; i < added.length; i++) added[i].remove()
    }
  })

  function start(stored) {
    if (stored && stored[STORE] && typeof stored[STORE] === "object") known = stored[STORE]
    observer = new MutationObserver(schedule)
    observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true })
    schedule()
  }

  try { chrome.storage.local.get(STORE, start) } catch (e) { start(null) }
})()
