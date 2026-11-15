import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.sette7blo.omanero"

  readonly property string pluginDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/io.github.sette7blo.omanero"

  // Service.qml instance, provided by Omarchy's plugin host.
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property var walletStatus: service ? service.status : null
  readonly property string level: Model.level(walletStatus)
  readonly property string requestId: service ? service.requestId : ""
  // Someone on the X page in front has a Monero address.
  readonly property bool tippable: walletStatus !== null && walletStatus.page.length > 0

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)

  // The accent means one thing: someone on the page in front can be tipped.
  // Otherwise dim while locked or not set up, plain once unlocked. The balance
  // is never on the bar, and syncing is the panel's business.
  readonly property color iconColor: tippable ? Commons.Color.accent
    : (level === "ready" || level === "syncing" ? foreground : dim)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("service" in target) target.service = root.service
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onServiceChanged: injectPanel()

  // A monero: link was clicked: bring the panel up. The first id seen after
  // a load is whatever was already on disk, so it does not open anything.
  property bool requestSeen: false
  property string lastRequestId: ""

  function noteRequest() {
    if (!service || !service.loaded) return
    var fresh = requestId !== "" && requestId !== lastRequestId
    lastRequestId = requestId
    if (!requestSeen) { requestSeen = true; return }
    if (fresh && !opened) open()
  }

  onRequestIdChanged: noteRequest()

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLoadedChanged() { root.noteRequest() }
  }

  // Panel contract for the bar's popout coordinator.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: Model.tooltip(root.walletStatus)
    iconComponent: Component {
      MoneroIcon {
        size: Style.bar.iconCanvas
        iconColor: root.iconColor
        strokeWidth: 2.2

        Behavior on iconColor {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: Style.duration(160) }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.togglePanel()
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.service && root.level !== "locked") root.service.lock()
      } else if (buttonCode === Qt.RightButton) {
        Util.execArgv(["xdg-open", root.pluginDir + "/README.md"])
      }
    }
  }
}
