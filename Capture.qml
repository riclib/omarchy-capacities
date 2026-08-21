import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One overlay, two modes. Capture is the one you reach for without thinking:
// a key, a thought, Enter, gone. Search is the same surface asking the space
// a question instead of telling it something.
//
// Both talk to bin/omarchy-capacities rather than the API directly — the
// token belongs in a 0600 file, and a capture that fails belongs in a queue
// on disk, neither of which the shell process should be holding.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest?.id || "riclib.capacities"
  // The registry stamps the directory it loaded this plugin from onto the
  // manifest, so a checkout under another name still finds its own bin/.
  readonly property string pluginDir: manifest?.__sourceDir
    || (Quickshell.env("HOME") + "/.config/omarchy/plugins/riclib.capacities")
  readonly property string cli: pluginDir + "/bin/omarchy-capacities"

  property bool opened: false
  property string mode: "capture"          // "capture" | "search"
  property string text: ""
  property var results: []
  property int selectedIndex: 0
  property bool searching: false
  // Enter means "search" while the query has moved on since the last one, and
  // "open what I picked" once it hasn't. Without this the key does the wrong
  // one of the two exactly when you are going fastest.
  property bool queryDirty: false

  property string spaceTitle: ""
  property int queuedCount: 0
  property bool tokenMissing: false
  property string statusError: ""

  readonly property bool isSearch: mode === "search"
  readonly property bool hasResults: results.length > 0

  // Shares the [menu] surface tokens, so a theme that styles the launcher
  // styles this too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Math.max(Style.space(38), Style.font.body + Style.spacing.rowPaddingX * 2)

  property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
  readonly property int inputHeight: Math.max(Style.space(34), contentText.contentHeight + Style.space(6))
  // Whole rows only. A list capped at an arbitrary pixel height ends in a row
  // sliced through the middle, which reads as a rendering fault rather than as
  // "there is more below".
  readonly property int visibleRows: Math.max(1, Math.floor(Style.space(320) / rowHeight))
  readonly property int listHeight: isSearch && hasResults
    ? Math.min(visibleRows, results.length) * rowHeight
    : 0
  property int cardHeight: Math.min(
    contentMargin * 2 + headerRow.height + inputHeight + listHeight + footer.height + Style.space(26),
    panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    var payload = Model.parseJson(payloadJson, {})
    root.mode = payload.mode === "search" ? "search" : "capture"
    root.opened = true
    root.text = ""
    root.results = []
    root.selectedIndex = 0
    root.queryDirty = false
    root.searching = false
    statusProcess.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function openSearch() {
    if (root.opened && root.isSearch) root.dismiss()
    else root.open('{"mode":"search"}')
  }

  function setMode(next) {
    if (root.mode === next) return
    root.mode = next
    root.results = []
    root.selectedIndex = 0
    root.queryDirty = root.text.length > 0
  }

  function setText(next) {
    root.text = next
    if (root.isSearch) root.queryDirty = true
  }

  // ---- capture -----------------------------------------------------------

  function submitCapture(asTask) {
    var captured = root.text
    root.dismiss()
    if (!captured.trim()) return
    // Detached on purpose: the capture is gone from the screen before the
    // request is made, and the CLI owns telling you if it could not be sent.
    var args = [root.cli, "capture"]
    if (asTask) args.push("--task")
    args.push(captured)
    Quickshell.execDetached(args)
  }

  function saveClipboardLink() {
    root.dismiss()
    Quickshell.execDetached([root.cli, "link"])
  }

  // ---- search ------------------------------------------------------------

  function runSearch() {
    var query = root.text.trim()
    if (!query) { root.results = []; return }
    root.searching = true
    searchProcess.command = [root.cli, "search", query]
    searchProcess.running = true
  }

  function select(delta) {
    root.selectedIndex = Model.clampIndex(root.selectedIndex + delta, root.results.length)
    // The view follows the selection rather than the other way around: walking
    // past the last visible row has to bring the next one into sight.
    if (resultList) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activate() {
    if (!root.hasResults) return
    var hit = root.results[Model.clampIndex(root.selectedIndex, root.results.length)]
    if (!hit) return
    root.dismiss()
    Quickshell.execDetached([root.cli, "open", hit.id])
  }

  Process {
    id: searchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.results = Model.parseSearch(text)
        root.selectedIndex = 0
        root.queryDirty = false
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw !== "") root.statusError = Model.elide(raw, 120)
      }
    }
    onExited: root.searching = false
  }

  Process {
    id: statusProcess
    command: [root.cli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = Model.parseStatus(text)
        root.spaceTitle = status.space
        root.queuedCount = status.queued
        root.tokenMissing = !status.token || status.authRequired
        root.statusError = status.error
      }
    }
  }

  // First-load setup: config file, menu rows, the CLI on PATH. Idempotent.
  Process {
    id: setupProcess
    command: [root.pluginDir + "/bin/capacities-setup"]
  }
  Component.onCompleted: setupProcess.running = true

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "capacities-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var isEnter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter

          if (event.key === Qt.Key_Escape) {
            // Esc walks back one step at a time — results, then text, then out.
            if (root.isSearch && root.hasResults) root.results = []
            else if (root.text) root.setText("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.setMode(root.isSearch ? "capture" : "search")
            event.accepted = true
          } else if (isEnter && (event.modifiers & Qt.ShiftModifier) && !root.isSearch) {
            root.setText(root.text + "\n")
            event.accepted = true
          } else if (isEnter && (event.modifiers & Qt.ControlModifier) && !root.isSearch) {
            root.submitCapture(true)
            event.accepted = true
          } else if (isEnter) {
            if (!root.isSearch) root.submitCapture(false)
            else if (root.queryDirty || !root.hasResults) root.runSearch()
            else root.activate()
            event.accepted = true
          } else if (root.isSearch && event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (root.isSearch && event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.text)) {
            root.setText(Util.editedFilter(event, root.text))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setText(root.text + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Column {
          anchors.fill: parent
          spacing: Style.space(10)

          Row {
            id: headerRow
            width: parent.width
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              // nf-md-lightbulb_outline — the space's own icon is a lightbulb.
              text: root.isSearch ? "󰅉" : "󰔏"
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.tokenMissing
                ? "Capacities — not connected"
                : (root.isSearch ? "Search " : "Capture to ") + (root.spaceTitle || "Capacities")
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item { width: Math.max(0, headerRow.width - headerRow.spacing * 3 - x); height: 1 }
          }

          // What was typed. Rendered as plain text because a capture is text,
          // never markup: under AutoText a thought like "<div> needs margin"
          // is guessed to be rich text, the tags vanish from the card, and the
          // file still gets the literal characters.
          Text {
            id: contentText
            width: parent.width
            text: root.text || (root.isSearch ? "Search your space…" : "What happened?")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: root.text ? 1 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
          }

          ListView {
            id: resultList
            visible: root.isSearch && (root.hasResults || root.searching)
            width: parent.width
            height: root.listHeight
            clip: true
            model: root.results
            currentIndex: root.selectedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property var modelData
              required property int index

              width: resultList.width
              height: root.rowHeight
              radius: Style.space(6)
              color: index === root.selectedIndex ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - structureLabel.width - parent.spacing
                  text: modelData.title
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: index === root.selectedIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  id: structureLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.structure
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.selectedIndex = index
                  root.activate()
                }
              }
            }
          }

          Text {
            id: footer
            width: parent.width
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            text: {
              if (root.tokenMissing)
                return "Run  omarchy-capacities login --token cap-api-…  to connect"
              if (root.statusError)
                return Model.elide(root.statusError, 90)
              if (root.searching)
                return "Searching…"
              var queued = root.queuedCount > 0
                ? "   ·   " + root.queuedCount + " queued offline"
                : ""
              return root.isSearch
                ? "Enter search   ·   ↑↓ pick   ·   Enter open   ·   Tab capture   ·   Esc close" + queued
                : "Enter capture   ·   Ctrl+Enter as task   ·   Shift+Enter newline   ·   Tab search" + queued
            }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "riclib.capacities"

    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function show(): void { root.open("{}") }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function search(): void { root.openSearch() }
    function link(): void { root.saveClipboardLink() }
  }
}
