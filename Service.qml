import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Background service. On load it runs install.sh, which finishes anything
// omarchy plugin add does not: wallet tools, the command, monero: links, and
// the X extension. It also polls the wallet and runs one command at a time
// for the panel. Secrets go to the command on stdin as a single JSON line
// and are dropped as soon as they are written.
Item {
  id: root

  property var shell: null
  property bool panelOpen: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: home + "/.config/omarchy/plugins/" + Model.PLUGIN_ID
  readonly property string cli: pluginDir + "/bin/omanero"
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
  property var plugins: []
  property bool pluginsLoaded: false

  readonly property string requestId: status.request ? status.request.id : ""

  signal finished(string kind, bool ok)

  // --- Internal ------------------------------------------------------------
  property var queue: []
  property var current: null
  property string pendingInput: ""
  // Set when a wallet is created while a status run is still out: that run
  // looked before the wallet existed, so its "locked" says nothing about it.
  property bool statusOutdated: false

  // --- Commands ------------------------------------------------------------
  // A name adds another wallet; without one the first wallet is made.
  function create(password, name) {
    enqueue("create", ["create"], { password: String(password || ""), name: String(name || "") })
  }
  function restore(seed, password, restoreHeight, name) {
    enqueue("restore", ["restore"], {
      seed: String(seed || ""), password: String(password || ""), restoreHeight: String(restoreHeight || ""),
      name: String(name || "")
    })
  }
  function removeWallet(name) {
    root.review = null
    root.receipt = null
    root.transfers = []
    root.transfersLoaded = false
    root.qr = null
    enqueue("forget", ["forget"], { name: String(name || "") })
  }
  function unlock(password) {
    enqueue("unlock", ["unlock"], { password: String(password || "") })
  }
  // Locking also takes a new seed off the screen, written down or not: what
  // is locked must not stay readable to whoever walks up next. `omanero seed`
  // shows it again after unlocking.
  function lock() {
    root.seedInfo = null
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
  function loadPlugins() { enqueue("plugins", ["plugins"], null) }
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
    if (kind === "create") {
      root.seedInfo = Model.parseSeed(res)
      root.statusOutdated = statusProc.running
    } else if (kind === "preview") root.review = Model.parseReview(res)
    else if (kind === "relay") {
      root.receipt = Model.parseReceipt(res)
      root.review = null
      root.transfersLoaded = false
    } else if (kind === "history") {
      root.transfers = Model.parseTransfers(res)
      root.transfersLoaded = true
    } else if (kind === "qr") {
      root.qr = Model.parseQr(res)
    } else if (kind === "plugins") {
      root.plugins = Model.parsePlugins(res)
      root.pluginsLoaded = true
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
      var outdated = root.statusOutdated
      root.statusOutdated = false
      if (next) {
        if (JSON.stringify(next) !== JSON.stringify(root.status)) root.status = next
        if (!next.unlocked) {
          // Locked from a terminal or by the idle timer.
          if (!outdated) root.seedInfo = null
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
  // install.sh --if-needed exits at once when this machine is already set up.
  // A missing package opens a terminal for the password, then the installer
  // finishes there. The status timer picks up the new tools.
  Process {
    id: installProc
    running: false
  }

  Component.onCompleted: {
    installProc.command = [root.pluginDir + "/install.sh", "--if-needed"]
    installProc.running = true
    root.refresh()
  }
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
