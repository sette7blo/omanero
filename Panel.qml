import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.sette7blo.omanero"
  ipcTarget: "io.github.sette7blo.omanero"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool showSettings: false
  property string tab: "send"
  property string setupMode: "create"
  property string formError: ""
  property bool copied: false
  property bool showQr: false
  property var pickedTip: null
  // Adding another wallet next to the ones that exist.
  property bool addingWallet: false
  property bool confirmRemove: false
  // The short wallet list under the header, opened from its button or with W.
  property bool pickingWallet: false
  readonly property bool canPickWallet: st.walletExists && st.wallets.length > 1
    && (view === "wallet" || view === "locked")
  property string appliedRequest: ""

  // Settings draft, filled when the settings view opens.
  property string draftNetwork: "mainnet"

  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var st: service ? service.status : Model.emptyStatus()
  readonly property bool busy: service ? service.busy === true : false
  readonly property var request: st.request
  readonly property string requestId: request ? request.id : ""
  readonly property var seedInfo: service ? service.seedInfo : null
  readonly property var review: service ? service.review : null
  readonly property var receipt: service ? service.receipt : null
  // Only a code for the address on screen is drawn; one left over from another
  // network or wallet is not.
  readonly property var qr: service && service.qr && service.qr.address === st.address ? service.qr : null

  // loading | missing | seed | settings | setup | locked | wallet
  readonly property string view: {
    if (!service || !service.loaded) return "loading"
    if (!st.installed) return "missing"
    if (seedInfo) return "seed"
    if (showSettings) return "settings"
    if (!st.walletExists || addingWallet) return "setup"
    if (!st.unlocked) return "locked"
    return "wallet"
  }

  readonly property bool typing: seedField.activeFocus || heightField.activeFocus
    || newPassField.activeFocus || repeatPassField.activeFocus || unlockField.activeFocus
    || addressField.activeFocus || amountField.activeFocus || nodeField.activeFocus
    || lockField.field.activeFocus || nameField.activeFocus

  // 0 to 3, stepped by a timer while a command runs.
  property int busyStep: 0
  readonly property string busyDots: "...".slice(0, busyStep) + "   ".slice(busyStep)
  readonly property string busyLine: busyText !== "" ? busyText + (Style.reduceMotion ? "..." : busyDots) : ""
  readonly property bool settingUp: busy && service !== null
    && (service.busyKind === "create" || service.busyKind === "restore")

  readonly property string busyText: {
    if (!busy || !service) return ""
    var kind = service.busyKind
    if (kind === "create") return "Creating the wallet"
    if (kind === "restore") return "Restoring the wallet"
    if (kind === "unlock") return "Opening the wallet"
    if (kind === "lock") return "Saving and locking"
    if (kind === "preview") return "Building the transaction"
    if (kind === "relay") return "Sending"
    if (kind === "config") return "Saving"
    if (kind === "forget") return "Removing the wallet"
    return ""
  }

  readonly property string errorText: formError !== "" ? formError : (service ? service.error : "")

  readonly property var historyRows: Model.transferRows(service ? service.transfers : [], Date.now())

  function clearMessages() {
    root.formError = ""
    if (root.service) root.service.clearError()
  }

  function clearSecrets() {
    seedField.text = ""
    newPassField.text = ""
    repeatPassField.text = ""
    unlockField.text = ""
  }

  function submitSetup() {
    if (root.busy || !root.service) return
    clearMessages()
    var problem = Model.passwordProblem(newPassField.text, repeatPassField.text)
    if (root.setupMode === "restore") {
      problem = Model.seedProblem(seedField.text) || (heightField.text.trim() === ""
        ? "Enter the restore height: a block number or a date." : "") || problem
    }
    var name = root.addingWallet ? nameField.text.trim().toLowerCase() : ""
    if (root.addingWallet) problem = Model.walletNameProblem(name, root.st.wallets) || problem
    if (problem !== "") { root.formError = problem; return }
    if (root.setupMode === "restore") root.service.restore(seedField.text, newPassField.text, heightField.text, name)
    else root.service.create(newPassField.text, name)
  }

  function startAddWallet() {
    clearMessages()
    clearSecrets()
    nameField.text = ""
    root.setupMode = "create"
    root.showSettings = false
    root.addingWallet = true
  }

  function switchWallet(name) {
    root.pickingWallet = false
    if (root.busy || !root.service || name === root.st.wallet) return
    clearMessages()
    root.resetSend()
    root.service.saveConfig({ wallet: name })
  }

  function stepTab(direction) {
    if (root.view === "wallet" && !root.review) root.tab = Model.nextTab(root.tab, direction)
  }

  // 1 to 4 pick a tab, W opens the wallet list, L (with Shift) locks. Plain l
  // belongs to the shell's h/l movement, which steps through the tabs.
  function handleKey(text) {
    var tab = Model.tabForKey(text)
    if (tab !== "" && root.view === "wallet" && !root.review) { root.tab = tab; return }
    if ((text === "w" || text === "W") && root.canPickWallet) { root.pickingWallet = !root.pickingWallet; return }
    if (text === "L" && root.view === "wallet" && root.service && !root.busy) root.service.lock()
  }

  function submitUnlock() {
    if (root.busy || !root.service) return
    clearMessages()
    if (unlockField.text === "") { root.formError = "Enter the wallet password."; return }
    root.service.unlock(unlockField.text)
  }

  function submitReview() {
    if (root.busy || !root.service) return
    clearMessages()
    var problem = Model.sendProblem(addressField.text, amountField.text, root.st.network)
    if (problem !== "") { root.formError = problem; return }
    root.service.previewSend(addressField.text.replace(/\s+/g, ""), amountField.text.replace(/\s+/g, ""))
  }

  function pickTip(item) {
    clearMessages()
    root.pickedTip = item
    addressField.text = item.address
    amountField.forceActiveFocus()
  }

  function resetSend() {
    root.pickedTip = null
    addressField.text = ""
    amountField.text = ""
    if (root.service) {
      root.service.cancelReview()
      root.service.clearReceipt()
    }
  }

  function applyRequest() {
    if (root.requestId === "" || root.requestId === root.appliedRequest) return
    root.appliedRequest = root.requestId
    root.pickedTip = null
    root.showSettings = false
    root.tab = "send"
    clearMessages()
    if (root.service) {
      root.service.cancelReview()
      root.service.clearReceipt()
    }
    addressField.text = root.request.address
    amountField.text = root.request.amount
  }

  function openSettings() {
    root.draftNetwork = root.st.network
    nodeField.text = root.st.customNode
    lockField.value = root.st.autoLockMinutes
    clearMessages()
    root.confirmRemove = false
    root.showSettings = true
  }

  function saveSettings() {
    if (root.busy || !root.service) return
    clearMessages()
    var changes = { autoLockMinutes: lockField.value }
    if (root.draftNetwork !== root.st.network) changes.network = root.draftNetwork
    else changes.node = nodeField.text.trim()
    root.service.saveConfig(changes)
  }

  // Read again each time the tab is shown: a plugin may have been installed
  // or removed since.
  function loadPluginsIfShown() {
    if (root.opened && root.view === "wallet" && root.tab === "plugins" && root.service) root.service.loadPlugins()
  }

  function pickPlugin(item) {
    root.tab = "send"
    pickTip(item)
  }

  function loadHistoryIfShown() {
    if (root.opened && root.view === "wallet" && root.tab === "history"
        && root.service && !root.service.transfersLoaded) root.service.loadHistory()
  }

  onRequestIdChanged: applyRequest()
  onTabChanged: { clearMessages(); loadHistoryIfShown(); loadPluginsIfShown() }
  onViewChanged: { root.formError = ""; loadHistoryIfShown() }
  onSetupModeChanged: clearMessages()

  Connections {
    target: root
    function onOpenedChanged() {
      if (root.service) root.service.panelOpen = root.opened
      if (!root.opened) {
        root.showSettings = false
        root.copied = false
        root.showQr = false
        root.addingWallet = false
        root.confirmRemove = false
        root.pickingWallet = false
        root.clearSecrets()
      } else {
        root.applyRequest()
        root.loadHistoryIfShown()
      }
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onFinished(kind, ok) {
      // A password or seed stays in a field only until the command it was
      // typed for has run.
      if (kind === "create" || kind === "restore" || kind === "unlock") root.clearSecrets()
      if (kind === "restore" && ok) heightField.text = ""
      if ((kind === "create" || kind === "restore") && ok) root.addingWallet = false
      if (kind === "forget") { root.confirmRemove = false; if (ok) root.showSettings = false }
      if (kind === "relay" && ok) { addressField.text = ""; amountField.text = ""; root.pickedTip = null }
      if (kind === "config" && ok) root.showSettings = false
      if (kind === "dismiss") root.resetSend()
      root.loadHistoryIfShown()
    }
  }

  Timer {
    interval: 400
    repeat: true
    running: root.busy && root.opened && !Style.reduceMotion
    onRunningChanged: root.busyStep = 0
    onTriggered: root.busyStep = (root.busyStep + 1) % 4
  }

  Timer {
    interval: 2000
    running: root.copied
    onTriggered: root.copied = false
  }

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component Body: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    color: root.foreground
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component Note: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    color: root.dim
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  component Field: Column {
    property alias label: fieldLabel.text
    default property alias content: fieldBody.data
    width: parent ? parent.width : implicitWidth
    spacing: Style.spacing.md
    FieldLabel { id: fieldLabel }
    Column {
      id: fieldBody
      width: parent.width
      spacing: Style.spacing.md
    }
  }

  component PanelButton: Button {
    bordered: true
    enabled: !root.busy
    opacity: enabled ? 1 : 0.45
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  // One line of the payment review: a dim name over its value.
  component ReviewLine: Column {
    property alias name: lineName.text
    property alias value: lineValue.text
    property bool strong: false
    width: parent ? parent.width : implicitWidth
    spacing: Style.spacing.xxs
    FieldLabel { id: lineName }
    Text {
      id: lineValue
      textFormat: Text.PlainText
      width: parent.width
      color: root.foreground
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: parent.strong
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: root.typing
      onCloseRequested: {
        if (root.pickingWallet) root.pickingWallet = false
        else root.close()
      }
      onTabRequested: function(direction) { root.stepTab(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.stepTab(dx) }
      onTextKey: function(text, modifiers) { root.handleKey(text) }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.xxl

      PanelHero {
        title: root.view === "wallet" || root.view === "locked" ? Model.heroTitle(root.st) : "Monero"
        meta: root.view === "settings" ? "Settings" : Model.heroMeta(root.st)
        detail: root.view === "wallet" ? Model.syncLine(root.st) : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconComponent: Component {
          MoneroIcon {
            size: Style.font.display
            iconColor: root.foreground
            strokeWidth: 1.75
          }
        }
        trailingControl: Component {
          Row {
            spacing: Style.spacing.md

            PanelActionButton {
              visible: root.canPickWallet
              iconText: "\u{f0584}"
              tooltipText: root.pickingWallet ? "Close the wallet list" : "Switch wallet (W)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.pickingWallet = !root.pickingWallet
            }
            PanelActionButton {
              visible: root.view === "wallet"
              iconText: "\u{f033e}"
              tooltipText: "Lock (Shift+L)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service && !root.busy) root.service.lock()
            }
            PanelActionButton {
              visible: root.view !== "loading" && root.view !== "missing" && root.view !== "seed"
              iconText: root.showSettings ? "\u{f0156}" : "\u{f0493}"
              tooltipText: root.showSettings ? "Close settings" : "Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.showSettings) root.showSettings = false
                else root.openSettings()
              }
            }
          }
        }
      }

      PanelSeparator { foreground: root.foreground }

      // ---- Wallet tools missing ----
      Column {
        width: parent.width
        spacing: Style.spacing.lg
        visible: root.view === "missing"

        Body { text: "Omanero is installing the Monero wallet tools." }
        Note { text: "A terminal opens if your password is needed. Only the wallet part is used. No blockchain is downloaded and no node runs on this computer." }
      }

      // ---- Wallet list, under the header ----
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.pickingWallet && root.canPickWallet

        FieldLabel { text: "Switch to" }
        Flow {
          width: parent.width
          spacing: Style.spacing.md
          Repeater {
            model: root.st.wallets
            PanelButton {
              required property var modelData
              text: modelData.name
              selected: modelData.name === root.st.wallet
              onClicked: root.switchWallet(modelData.name)
            }
          }
        }
        Note { text: "Switching locks the open wallet. Each wallet has its own password." }
      }

      // ---- Create or restore ----
      Column {
        width: parent.width
        spacing: Style.spacing.xxl
        visible: root.view === "setup"

        ButtonGroup {
          options: [{ value: "create", label: "New wallet" }, { value: "restore", label: "Restore from seed" }]
          value: root.setupMode
          focusable: false
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setupMode = value }
        }

        Field {
          label: "Name for this wallet"
          visible: root.addingWallet
          TextField {
            id: nameField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            placeholderText: "tips"
            foreground: root.foreground
            accent: root.accent
          }
          Note { text: "Lowercase letters, digits and dashes. Your other wallets stay as they are; this one has its own seed and password." }
        }

        Field {
          label: "25-word seed"
          visible: root.setupMode === "restore"
          TextField {
            id: seedField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            password: true
            placeholderText: "Paste or type the 25 words"
            foreground: root.foreground
            accent: root.accent
          }
        }

        Field {
          label: "Restore height"
          visible: root.setupMode === "restore"
          TextField {
            id: heightField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            placeholderText: "Block number, or a date like 2024-03-15"
            foreground: root.foreground
            accent: root.accent
          }
          Note { text: "The wallet scans from here. Use when the wallet was first made: earlier is safe but slower, later can hide money." }
        }

        Field {
          label: "Password"
          TextField {
            id: newPassField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            password: true
            foreground: root.foreground
            accent: root.accent
          }
        }

        Field {
          label: "Repeat password"
          TextField {
            id: repeatPassField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            password: true
            foreground: root.foreground
            accent: root.accent
            onAccepted: root.submitSetup()
          }
          Note { text: "Encrypts the wallet file on this computer. It is not the seed and cannot bring a lost wallet back." }
        }

        PanelButton {
          text: root.settingUp ? root.busyLine
            : (root.setupMode === "restore" ? "Restore wallet" : "Create wallet")
          onClicked: root.submitSetup()
        }

        Note {
          visible: root.settingUp
          text: root.service && root.service.busyKind === "restore"
            ? "This can take a minute or more."
            : "This can take up to a minute. The seed appears next; have paper ready."
        }

        PanelButton {
          visible: root.addingWallet
          text: "Cancel"
          onClicked: { root.clearMessages(); root.clearSecrets(); root.addingWallet = false }
        }

        Note { text: Model.networkLine(root.st) }
      }

      // ---- Seed, shown once after creating ----
      Column {
        width: parent.width
        spacing: Style.spacing.xxl
        visible: root.view === "seed"

        Body { text: "Write these 25 words down and keep them off this computer. Anyone who has them has the money, and they are the only way to get the wallet back." }

        Rectangle {
          width: parent.width
          height: seedText.implicitHeight + Style.spacing.xxl * 2
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

          Text {
            id: seedText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.spacing.xxl
            text: root.seedInfo ? root.seedInfo.seed : ""
            color: root.foreground
            wrapMode: Text.WordWrap
            lineHeight: 1.3
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        ReviewLine {
          name: "Restore height"
          value: root.seedInfo ? String(root.seedInfo.restoreHeight) : ""
        }
        Note { text: "Keep this number with the words. Restoring asks for it." }
        Note { text: "Locking the wallet takes the words off the screen. To see them again, unlock it and run omanero seed in a terminal." }

        PanelButton {
          text: "I wrote it down"
          onClicked: if (root.service) root.service.clearSeed()
        }
      }

      // ---- Locked ----
      Column {
        width: parent.width
        spacing: Style.spacing.xxl
        visible: root.view === "locked"

        Body {
          visible: root.request !== null
          text: root.request ? "Unlock to pay " + Model.shortAddress(root.request.address)
            + (root.request.amount !== "" ? " " + root.request.amount + " XMR" : "") : ""
        }

        Body {
          visible: root.request === null && root.st.page.length > 0
          text: "Unlock to tip " + Model.tipNames(root.st.page)
        }

        Field {
          label: Model.walletLabel(root.st) !== "" ? "Password for " + Model.walletLabel(root.st) : "Wallet password"
          TextField {
            id: unlockField
            width: parent.width
            enabled: !root.busy
            opacity: enabled ? 1 : 0.45
            password: true
            foreground: root.foreground
            accent: root.accent
            onAccepted: root.submitUnlock()
          }
        }

        PanelButton {
          text: root.busy && root.service && root.service.busyKind === "unlock" ? root.busyLine : "Unlock"
          onClicked: root.submitUnlock()
        }

        Note { text: Model.networkLine(root.st) }
      }

      // ---- Wallet ----
      Column {
        width: parent.width
        spacing: Style.spacing.xxl
        visible: root.view === "wallet"

        ButtonGroup {
          options: [
            { value: "send", label: "Send" },
            { value: "receive", label: "Receive" },
            { value: "history", label: "History" },
            { value: "plugins", label: "Authors" }
          ]
          value: root.tab
          fontSize: Style.font.bodySmall
          focusable: false
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(value) { root.tab = value }
        }

        // -- Send: form
        Column {
          width: parent.width
          spacing: Style.spacing.xxl
          visible: root.tab === "send" && !root.review && !root.receipt

          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.request === null && root.st.page.length > 0

            FieldLabel { text: "On the page in front" }
            Repeater {
              model: root.st.page

              PanelButton {
                required property var modelData
                text: "Tip " + Model.tipName(modelData)
                selected: root.pickedTip !== null && root.pickedTip.address === modelData.address
                  && addressField.text === modelData.address
                onClicked: root.pickTip(modelData)
              }
            }
          }

          Note {
            visible: root.request === null && root.pickedTip !== null && addressField.text === root.pickedTip.address
            text: root.pickedTip ? Model.tipNote(root.pickedTip) : ""
          }

          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.request !== null

            FieldLabel { text: "From a payment link" }
            Body {
              visible: text !== ""
              text: root.request ? [root.request.recipient, root.request.description].filter(function(s) { return s !== "" }).join(": ") : ""
            }
            Note { text: "Check the address against the profile it came from before sending. A link can name any address." }
          }

          Field {
            label: "Pay to"
            TextField {
              id: addressField
              width: parent.width
              placeholderText: "Monero address"
              foreground: root.foreground
              accent: root.accent
            }
          }

          Field {
            label: "Amount in XMR"
            TextField {
              id: amountField
              width: parent.width
              placeholderText: "0.05"
              foreground: root.foreground
              accent: root.accent
              onAccepted: root.submitReview()
            }
            Note {
              text: root.st.unlockedBalance === root.st.balance
                ? "Spendable: " + root.st.unlockedBalance + " XMR"
                : "Spendable: " + root.st.unlockedBalance + " of " + root.st.balance + " XMR. The rest is waiting for confirmations."
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.lg

            PanelButton {
              text: "Review"
              onClicked: root.submitReview()
            }
            Item { Layout.fillWidth: true }
            PanelButton {
              visible: root.request !== null || addressField.text !== "" || amountField.text !== ""
              text: "Clear"
              onClicked: {
                root.clearMessages()
                if (root.request !== null && root.service) root.service.dismissRequest()
                else root.resetSend()
              }
            }
          }
        }

        // -- Send: review, nothing has left the wallet yet
        Column {
          width: parent.width
          spacing: Style.spacing.xxl
          visible: root.tab === "send" && root.review !== null

          ReviewLine { name: "Pay to"; value: root.review ? Model.groupedAddress(root.review.address) : "" }
          ReviewLine { name: "Amount"; value: root.review ? root.review.amount + " XMR" : "" }
          ReviewLine { name: "Network fee"; value: root.review ? root.review.fee + " XMR" : "" }
          ReviewLine { name: "Total"; strong: true; value: root.review ? root.review.total + " XMR" : "" }
          Note { text: "A Monero payment cannot be reversed. Read the address through once more." }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.lg

            PanelButton {
              text: "Back"
              onClicked: if (root.service) root.service.cancelReview()
            }
            Item { Layout.fillWidth: true }
            PanelButton {
              text: root.review ? "Send " + root.review.amount + " XMR" : "Send"
              selected: true
              onClicked: if (root.service && !root.busy) root.service.relay()
            }
          }
        }

        // -- Send: done
        Column {
          width: parent.width
          spacing: Style.spacing.xxl
          visible: root.tab === "send" && root.receipt !== null && !root.review

          Body { text: root.receipt ? "Sent " + root.receipt.amount + " XMR." : "" }
          ReviewLine {
            visible: value !== ""
            name: "Transaction"
            value: root.receipt ? root.receipt.txHash.replace(/(.{8})/g, "$1 ").trim() : ""
          }
          PanelButton {
            text: "Done"
            onClicked: if (root.service) root.service.clearReceipt()
          }
        }

        // -- Receive
        Column {
          width: parent.width
          spacing: Style.spacing.xxl
          visible: root.tab === "receive"

          // Each module is a whole number of pixels so the code stays crisp.
          // The white card and its quiet zone are fixed, whatever the theme.
          Rectangle {
            id: qrCard
            readonly property int size: root.qr ? root.qr.size : 0
            readonly property int moduleSize: size > 0 ? Math.max(3, Math.floor(Style.space(220) / size)) : 0

            visible: root.showQr && size > 0
            width: size * moduleSize
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            radius: Style.cornerRadius

            Grid {
              anchors.fill: parent
              columns: qrCard.size
              LayoutMirroring.enabled: false

              Repeater {
                model: qrCard.visible ? qrCard.size * qrCard.size : 0

                Rectangle {
                  required property int index
                  width: qrCard.moduleSize
                  height: qrCard.moduleSize
                  color: root.qr.rows[Math.floor(index / qrCard.size)].charAt(index % qrCard.size) === "1"
                    ? "#111111" : "transparent"
                }
              }
            }
          }

          ReviewLine { name: "Your address"; value: Model.groupedAddress(root.st.address) }
          RowLayout {
            width: parent.width
            spacing: Style.spacing.lg

            PanelButton {
              text: root.copied ? "Copied" : "Copy address"
              enabled: root.st.address !== ""
              onClicked: {
                // The address is re-checked by Model.address and passed as one argument.
                Util.execArgv(["wl-copy", "--", root.st.address])
                root.copied = true
              }
            }
            PanelButton {
              text: root.showQr ? "Hide QR code" : "Show QR code"
              enabled: root.st.address !== ""
              onClicked: {
                root.showQr = !root.showQr
                if (root.showQr && !root.qr && root.service) root.service.loadQr()
              }
            }
            Item { Layout.fillWidth: true }
          }
          Note { text: "Share this address to be paid. Incoming money shows up after the next block, about two minutes." }
        }

        // -- History
        Column {
          width: parent.width
          spacing: Style.spacing.lg
          visible: root.tab === "history"

          ListView {
            id: historyList
            width: parent.width
            height: Math.min(contentHeight, Style.space(320))
            visible: count > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.historyRows
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
              required property var modelData
              width: historyList.width
              implicitHeight: historyRow.implicitHeight + Style.spacing.md * 2

              Column {
                id: historyRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                RowLayout {
                  width: parent.width
                  spacing: Style.spacing.lg
                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: modelData.title
                    color: modelData.incoming ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.right
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: modelData.waiting
                  }
                }
                FieldLabel { text: modelData.subtitle }
              }
            }
          }

          Body {
            visible: historyList.count === 0
            color: root.dim
            text: root.service && root.service.transfersLoaded ? "No payments yet." : "Loading."
          }

          PanelButton {
            text: "Refresh"
            onClicked: if (root.service) root.service.loadHistory()
          }
        }

        // -- Authors: tip the authors of the plugins and apps that are installed
        Column {
          width: parent.width
          spacing: Style.spacing.lg
          visible: root.tab === "plugins"

          ListView {
            id: pluginList
            width: parent.width
            height: Math.min(contentHeight, Style.space(320))
            visible: count > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.service ? root.service.plugins : []
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
              required property var modelData
              width: pluginList.width
              implicitHeight: pluginRow.implicitHeight + Style.spacing.md * 2

              RowLayout {
                id: pluginRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.lg

                Column {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xxs
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  FieldLabel {
                    width: parent.width
                    text: Model.pluginSubtitle(modelData)
                    elide: Text.ElideMiddle
                  }
                }
                PanelButton {
                  text: "Tip"
                  onClicked: root.pickPlugin(modelData)
                }
              }
            }
          }

          Body {
            visible: pluginList.count === 0
            color: root.dim
            text: root.service && root.service.pluginsLoaded
              ? "None of your installed plugins or apps lists a Monero address yet." : "Loading."
          }
          Note { text: "Plugins list an address in manifest.json, apps in their AppStream file. The README explains both." }
        }
      }

      // ---- Settings ----
      Column {
        width: parent.width
        spacing: Style.spacing.xxl
        visible: root.view === "settings"

        Field {
          label: "Wallet"

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.st.wallets.length > 1

            Repeater {
              model: root.st.wallets

              PanelButton {
                required property var modelData
                text: modelData.name
                selected: modelData.name === root.st.wallet
                onClicked: root.switchWallet(modelData.name)
              }
            }
          }
          Note {
            visible: root.st.wallets.length > 1
            text: "Pressing another wallet locks this one and switches. Each has its own password."
          }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.lg
            visible: !root.confirmRemove

            PanelButton {
              text: "Add a wallet"
              onClicked: root.startAddWallet()
            }
            PanelButton {
              visible: root.st.walletExists
              text: "Remove this wallet"
              onClicked: { root.clearMessages(); root.confirmRemove = true }
            }
            Item { Layout.fillWidth: true }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.confirmRemove

            Body {
              text: "Remove the wallet " + root.st.wallet + " from omanero?"
            }
            Note {
              text: "Its files are moved aside, not deleted, but to reach the money again you need its 25-word seed. If you have not written the seed down, press Keep and do that first."
            }
            RowLayout {
              width: parent.width
              spacing: Style.spacing.lg
              PanelButton {
                text: "Keep"
                onClicked: root.confirmRemove = false
              }
              Item { Layout.fillWidth: true }
              PanelButton {
                text: "Remove " + root.st.wallet
                onClicked: if (root.service && !root.busy) root.service.removeWallet(root.st.wallet)
              }
            }
          }
        }

        Field {
          label: "Network"
          ButtonGroup {
            options: [{ value: "mainnet", label: "Mainnet" }, { value: "stagenet", label: "Stagenet" }]
            value: root.draftNetwork
            focusable: false
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onChanged: function(value) { root.draftNetwork = value }
          }
          Note { text: "Stagenet is play money for testing. Each network has its own wallet." }
        }

        Field {
          label: "Node"
          visible: root.draftNetwork === root.st.network
          TextField {
            id: nodeField
            width: parent.width
            placeholderText: root.st.nodes.length ? root.st.nodes[0] : "host:port"
            foreground: root.foreground
            accent: root.accent
          }
          Repeater {
            model: root.st.nodes
            delegate: Button {
              required property var modelData
              required property int index
              width: parent.width
              text: modelData
              leftAlign: true
              bordered: true
              selected: nodeField.text.trim() === modelData || (nodeField.text.trim() === "" && index === 0)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: nodeField.text = index === 0 ? "" : modelData
            }
          }
          Note { text: "Any public node works; these are the ones Cake Wallet ships. A node sees your IP address and the payments you send through it, never your keys." }
        }

        Note {
          visible: root.draftNetwork !== root.st.network
          text: "Save to switch network. You can pick a node for it afterwards."
        }

        NumberField {
          id: lockField
          width: parent.width
          label: "Lock after idle minutes (0 for never)"
          from: 0
          to: 1440
          stepSize: 5
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onModified: function(v) { lockField.value = v }
        }

        Note { text: "Changing the network or the node locks the wallet." }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.lg

          Item { Layout.fillWidth: true }
          PanelButton {
            text: "Save"
            selected: true
            onClicked: root.saveSettings()
          }
        }
      }

      // ---- Progress and errors, shared by every view ----
      FieldLabel {
        visible: root.busyText !== ""
        text: root.busyLine
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.errorText !== "" && root.busyText === ""
        text: root.errorText
        color: Commons.Color.urgent
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
