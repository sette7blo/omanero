import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Background service: the only thing here that runs bin/omanero. It polls
// the wallet's status and runs one command at a time for the panel. Secrets
// go to the command on stdin as a single JSON line and are dropped as soon
// as they are written.
Item {
  id: root

  property var shell: null
  property bool panelOpen: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cli: home + "/.config/omarchy/plugins/" + Model.PLUGIN_ID + "/bin/omanero"
  readonly property string stateDir: home + "/.local/state/omarchy/omanero/"

  // --- State exposed to the widget and the panel ---------------------------
  property var status: Model.emptyStatus()
  property bool loaded: false
  property bool busy: false
  property string busyKind: ""
  property string error: ""
  property var seedInfo: null
  property var review: null
  property var receipt: null
  property var transfers: []
  property bool transfersLoaded: false
  property var qr: null

  readonly property string requestId: status.request ? status.request.id : ""

  signal finished(string kind, bool ok)

  // --- Internal ------------------------------------------------------------
  property var queue: []
  property var current: null
  property string pendingInput: ""

  // --- Commands ------------------------------------------------------------
  function create(password) {
    enqueue("create", ["create"], { password: String(password || "") })
  }
  function restore(seed, password, restoreHeight) {
    enqueue("restore", ["restore"], {
      seed: String(seed || ""), password: String(password || ""), restoreHeight: String(restoreHeight || "")
    })
  }
  function unlock(password) {
    enqueue("unlock", ["unlock"], { password: String(password || "") })
  }
  function lock() {
    root.review = null
    root.receipt = null
    root.transfers = []
    root.transfersLoaded = false
    root.qr = null
    enqueue("lock", ["lock"], null)
  }
  function previewSend(address, amount) {
    root.receipt = null
    enqueue("preview", ["preview"], { address: String(address || ""), amount: String(amount || "") })
  }
  function relay() {
    if (!root.review) return
    enqueue("relay", ["relay"], { id: root.review.id })
  }
  function cancelReview() {
    root.review = null
    root.error = ""
  }
  function clearReceipt() { root.receipt = null }
  function clearSeed() { root.seedInfo = null }
  function clearError() { root.error = "" }
  function loadHistory() { enqueue("history", ["history"], null) }
  function loadQr() { enqueue("qr", ["qr"], null) }
  function dismissRequest() { enqueue("dismiss", ["dismiss"], null) }
  function saveConfig(changes) { enqueue("config", ["config", "apply"], { set: changes }) }

  function enqueue(kind, args, input) {
    for (var i = 0; i < root.queue.length; i++) {
      if (root.queue[i].kind === kind) return
    }
    if (root.current && root.current.kind === kind) return
    root.queue = root.queue.concat([{
      kind: kind, args: args, input: input === null ? "" : JSON.stringify(input) + "\n"
    }])
    pump()
  }

  function pump() {
    if (cmdProc.running || !root.queue.length) return
    var next = root.queue[0]
    root.queue = root.queue.slice(1)
    root.current = { kind: next.kind }
    root.pendingInput = next.input
    root.busy = true
    root.busyKind = next.kind
    root.error = ""
    cmdProc.command = [root.cli, "--json"].concat(next.args)
    cmdProc.running = true
  }

  function handle(kind, res) {
    if (!res.ok) {
      // History is a background fetch; a busy wallet is not worth a red line.
      if (kind !== "history") root.error = res.error
      return
    }
    if (kind === "create") root.seedInfo = Model.parseSeed(res)
    else if (kind === "preview") root.review = Model.parseReview(res)
    else if (kind === "relay") {
      root.receipt = Model.parseReceipt(res)
      root.review = null
      root.transfersLoaded = false
    } else if (kind === "history") {
      root.transfers = Model.parseTransfers(res)
      root.transfersLoaded = true
    } else if (kind === "qr") {
      root.qr = Model.parseQr(res)
    }
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = root.panelOpen
      ? [root.cli, "--json", "status", "--active"] : [root.cli, "--json", "status"]
    statusProc.running = true
  }

  // --- Processes -----------------------------------------------------------
  Process {
    id: cmdProc
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: cmdOut; waitForEnd: true }
    onRunningChanged: {
      if (running && root.pendingInput !== "") cmdProc.write(root.pendingInput)
      root.pendingInput = ""
    }
    onExited: function(code) {
      var kind = root.current ? root.current.kind : ""
      var res = Model.parseResult(String(cmdOut.text || ""))
      root.current = null
      root.busy = false
      root.busyKind = ""
      root.handle(kind, res)
      root.finished(kind, res.ok === true)
      root.refresh()
      Qt.callLater(root.pump)
    }
  }

  Process {
    id: statusProc
    running: false
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(code) {
      var next = Model.parseStatus(String(statusOut.text || ""))
      if (next) {
        if (JSON.stringify(next) !== JSON.stringify(root.status)) root.status = next
        if (!next.unlocked) {
          root.review = null
          root.transfers = []
          root.transfersLoaded = false
          root.qr = null
        }
      }
      root.loaded = true
    }
  }

  // bin/omanero writes request.json when a monero: link or a Tip control is
  // pressed, and page.json when the browser's front tab shows an address. The
  // first status run creates both, so the watches start once it is back.
  FileView {
    path: root.loaded ? root.stateDir + "request.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  FileView {
    path: root.loaded ? root.stateDir + "page.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  // --- Lifecycle -----------------------------------------------------------
  Component.onCompleted: root.refresh()
  onPanelOpenChanged: if (root.panelOpen) root.refresh()

  Timer {
    // Quick while someone is looking, slow otherwise. Each tick also lets
    // the tool lock the wallet once it has sat idle long enough.
    interval: root.panelOpen ? 4000 : (root.status.unlocked ? 20000 : 60000)
    running: true
    repeat: true
    onTriggered: if (!root.busy) root.refresh()
  }
}
