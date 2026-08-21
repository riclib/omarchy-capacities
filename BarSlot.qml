import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar slot for Capacities. Clicking opens the panel — today's note, what is
// open, what was made recently — which is also the answer to forgetting the
// keybinding. The badge is the one thing only the bar can say: a capture is
// still sitting in the outbox, unsent.
BarWidget {
  id: root
  moduleName: "riclib.capacities"

  // nf-md-lightbulb_on_outline, written as an escape rather than the literal
  // character: a raw private-use-area codepoint does not survive every editor
  // that touches this file, and when it is dropped the widget renders as a
  // bare number.
  readonly property string icon: "󰄏"
  readonly property bool showQueued: setting("showQueued", true) === true

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/capacities"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

  property int queued: 0
  readonly property bool holding: root.showQueued && root.queued > 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Watched, not polled: the outbox only changes when a capture fails or
  // drains, and inotify says so without a timer per monitor.
  FileView {
    path: root.statePath + "/outbox.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseJson(text(), [])
      root.queued = Array.isArray(parsed) ? parsed.length : 0
    }
    // No file is the ordinary case — nothing has ever failed to send.
    onLoadFailed: root.queued = 0
  }

  // ---- the panel ---------------------------------------------------------
  //
  // A bar surface exists per monitor, so this widget — and its panel — exist
  // per monitor. The panel is loaded here rather than mounted globally so the
  // one that opens is the one on the screen you are looking at.

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  // Shape contract for the bar's popout routing: open/close/opened have to
  // live on the widget root, which stands in for the panel as the bar's
  // popout identity — the same way the first-party panel widgets do.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.icon
                        : (root.holding ? root.icon + "  " + root.queued : root.icon)
    labelVisible: !root.vertical
    // The urgent colour is spent on the one state worth interrupting for:
    // something you captured has not reached the space yet.
    active: root.holding
    tooltipText: root.holding
      ? root.queued + (root.queued === 1 ? " capture waiting to send" : " captures waiting to send")
        + "\nclick to open   ·   middle click to capture"
      : "Capacities — click to open\nmiddle click to capture   ·   right click to search"

    onPressed: function(pressedButton) {
      if (!root.bar) return
      if (pressedButton === Qt.RightButton)
        root.bar.run("omarchy-shell riclib.capacities search")
      else if (pressedButton === Qt.MiddleButton)
        root.bar.run("omarchy-shell shell toggle riclib.capacities '{}'")
      else
        root.togglePanel()
    }
  }

  // An IPC target routes to exactly one handler, but this widget is live once
  // per monitor, so the instance that claimed the target is rarely the one you
  // are looking at — a keybinding would open the panel on whichever screen the
  // shell happened to register first. The bar already resolves this for its own
  // summons by asking Hyprland which output is focused; borrow that rather than
  // acting locally.
  function focusedInstance() {
    if (root.bar && typeof root.bar.findPanelWidget === "function") {
      var item = root.bar.findPanelWidget(root.moduleName)
      if (item) return item
    }
    return root
  }

  IpcHandler {
    target: "riclib.capacities.bar"

    function open(): void { root.focusedInstance().open() }
    function close(): void { root.focusedInstance().close() }
    function toggle(): void { root.focusedInstance().togglePanel() }

    // A refresh is not a place, so it goes to every instance.
    function sync(): void { root.broadcast("refreshPanel") }
  }

  function refreshPanel() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh(true)
  }
}
