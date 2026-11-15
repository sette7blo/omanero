// Carries what the front tab's page holds to the omanero wallet over native
// messaging, and passes on a press of a Tip control. The port stays open only
// while there is something to say; closing it clears the bar indicator.

var HOST = "io.github.sette7blo.omanero"
var pages = new Map()
var activeTab = -1
var port = null
var sent = "[]"
// Set when the wallet tool is not linked or turns this profile away, as it
// does for a web app running in its own profile. Pages are then told to show nothing.
var unavailable = false

function standDown(tabId) {
  chrome.tabs.sendMessage(tabId, { type: "off" }, function () { void chrome.runtime.lastError })
}

function connect() {
  if (port) return port
  try {
    port = chrome.runtime.connectNative(HOST)
  } catch (e) {
    port = null
    return null
  }
  var opened = port
  port.onDisconnect.addListener(function () {
    var error = chrome.runtime.lastError
    // Closing the port ourselves also lands here, with nothing to report.
    if (port === opened) {
      port = null
      sent = "[]"
    }
    if (error && /not found|forbidden|exited/i.test(String(error.message))) {
      unavailable = true
      pages.forEach(function (items, tabId) { standDown(tabId) })
    }
  })
  return port
}

function post(message) {
  var target = connect()
  if (!target) return
  try { target.postMessage(message) } catch (e) { port = null }
}

function publish() {
  var items = pages.get(activeTab) || []
  var body = JSON.stringify(items)
  if (body === sent) return
  sent = body
  if (items.length) post({ type: "page", items: items })
  else if (port) { port.disconnect(); port = null }
}

function front(tabId) {
  activeTab = tabId
  publish()
  // This script may have been asleep and lost what the tab said earlier.
  chrome.tabs.sendMessage(tabId, { type: "report" }, function () { void chrome.runtime.lastError })
}

chrome.runtime.onMessage.addListener(function (message, sender) {
  var tab = sender && sender.tab
  if (!tab || typeof tab.id !== "number" || !message) return
  if (unavailable) { standDown(tab.id); return }
  if (message.type === "page") {
    pages.set(tab.id, Array.isArray(message.items) ? message.items.slice(0, 5) : [])
    if (tab.active) activeTab = tab.id
    publish()
  } else if (message.type === "tip") {
    post({ type: "tip", address: message.address, handle: message.handle, source: message.source })
  }
})

chrome.tabs.onActivated.addListener(function (info) { front(info.tabId) })

chrome.tabs.onRemoved.addListener(function (tabId) {
  pages.delete(tabId)
  publish()
})

// A full page load drops whatever the tab held; X reports again if it is X.
chrome.tabs.onUpdated.addListener(function (tabId, change) {
  if (change.status !== "loading" || !pages.has(tabId)) return
  pages.delete(tabId)
  publish()
})

chrome.windows.onFocusChanged.addListener(function (windowId) {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return
  chrome.tabs.query({ active: true, windowId: windowId }, function (tabs) {
    void chrome.runtime.lastError
    if (tabs && tabs[0] && typeof tabs[0].id === "number") front(tabs[0].id)
  })
})
