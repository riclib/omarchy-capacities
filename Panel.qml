import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup behind the bar icon: what today's note has collected, what is
// still open, what was made recently — and the two ways in, capture and
// search.
//
// It never talks to the API. bin/omarchy-capacities owns the token and every
// request and writes data.json; this renders that file and shells back out
// for the actions. A row is a place, so clicking one opens it in Capacities.
Panel {
  id: root
  moduleName: "riclib.capacities"
  ipcTarget: "riclib.capacities.panel"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string cli: pluginDir + "bin/omarchy-capacities"

  readonly property color fg: Color.popups.text
  readonly property color muted: Qt.darker(fg, 1.6)

  // Named `cache`, not `data`: `data` is Item's default property — the list
  // of child objects — and shadowing it makes every read return children.
  property var cache: Model.parseData("")
  property bool syncing: false
  property double nowMs: Date.now()

  readonly property bool hasToday: cache.bullets.length > 0
  readonly property bool hasTasks: cache.tasks.length > 0
  readonly property bool hasRecent: cache.recent.length > 0

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
      + "/omarchy/capacities/data.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.cache = Model.parseData(text())
    onLoadFailed: root.cache = Model.parseData("")
  }

  // Opening is the only thing that syncs. --max-age lets a second monitor's
  // panel skip a refresh the first one just did, and keeps repeated opens off
  // the API's thirty-a-minute allowance.
  function refresh(force) {
    if (syncProcess.running) return
    root.nowMs = Date.now()
    syncProcess.command = force
      ? [root.cli, "sync"]
      : [root.cli, "sync", "--max-age", "120"]
    root.syncing = true
    syncProcess.running = true
  }

  Process {
    id: syncProcess
    onExited: root.syncing = false
  }

  onOpenedChanged: if (opened) refresh(false)

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
  }

  function openObject(objectId, blockId) {
    if (!objectId) return
    root.close()
    run(blockId ? ["open", objectId, "--block", blockId] : ["open", objectId])
  }

  function openCapture() {
    root.close()
    if (root.bar) root.bar.run("omarchy-shell shell toggle riclib.capacities '{}'")
  }

  function openSearch() {
    root.close()
    if (root.bar) root.bar.run("omarchy-shell riclib.capacities search")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Keys.onPressed: function(event) {
        if (event.text === "c") { root.openCapture(); event.accepted = true }
        else if (event.text === "s") { root.openSearch(); event.accepted = true }
        else if (event.text === "r") { root.refresh(true); event.accepted = true }
        else if (event.text === "t" && root.cache.noteId) {
          root.openObject(root.cache.noteId, ""); event.accepted = true
        }
      }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: content
        width: scroll.width
        spacing: Style.space(10)

        // ---- header
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, Style.space(24))

          Column {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              text: root.cache.space || "Capacities"
              color: root.fg
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              text: root.cache.authRequired
                ? "not connected — omarchy-capacities login"
                : (root.cache.error
                   ? Model.elide(root.cache.error, 46)
                   : (root.syncing ? "syncing…" : Model.syncedLabel(root.cache.syncedAt, root.nowMs)))
              color: root.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰏫"
              foreground: root.fg
              tooltipText: "Capture  (c)"
              onClicked: root.openCapture()
            }

            PanelActionButton {
              iconText: "󰅉"
              foreground: root.fg
              tooltipText: "Search  (s)"
              onClicked: root.openSearch()
            }

            PanelActionButton {
              iconText: "󰑐"
              foreground: root.fg
              tooltipText: "Sync now  (r)"
              onClicked: root.refresh(true)
            }
          }
        }

        // ---- today
        PanelSectionHeader {
          width: parent.width
          text: "TODAY"
          foreground: root.fg
        }

        Text {
          visible: !root.hasToday
          width: parent.width
          text: root.cache.authRequired ? "Connect a token to see today's note."
                                       : "Nothing captured today yet."
          color: root.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Repeater {
          model: root.cache.bullets

          // A bullet deep-links to its own block, so clicking the line you
          // half-remember writing puts the cursor on it rather than at the
          // top of a long day.
          PanelRow {
            required property var modelData
            width: content.width
            foreground: root.fg
            label: modelData.text
            indent: Math.min(2, modelData.depth || 0)
            onActivated: root.openObject(root.cache.noteId, modelData.id)
          }
        }

        // ---- tasks
        PanelSectionHeader {
          width: parent.width
          visible: root.hasTasks
          text: "OPEN TASKS"
          foreground: root.fg
        }

        Repeater {
          model: root.cache.tasks

          PanelRow {
            required property var modelData
            width: content.width
            foreground: root.fg
            label: modelData.title
            trailing: modelData.date ? String(modelData.date).slice(0, 10) : ""
            onActivated: root.openObject(modelData.id, "")
          }
        }

        // ---- recent
        PanelSectionHeader {
          width: parent.width
          visible: root.hasRecent
          text: "RECENT"
          foreground: root.fg
        }

        Repeater {
          model: root.cache.recent

          PanelRow {
            required property var modelData
            width: content.width
            foreground: root.fg
            label: modelData.title
            trailing: Model.shortAge(modelData.createdAt, root.nowMs)
            onActivated: root.openObject(modelData.id, "")
          }
        }

        // Recent can only hold types that carry a creation time; saying which
        // ones were left out beats a section that looks like it lost things.
        Text {
          visible: root.cache.recentSkipped.length > 0
          width: parent.width
          // The type list is cached for twelve hours, so enabling the property
          // is only half of it — say the other half rather than letting it
          // look like the change did nothing.
          text: "No creation time on: " + root.cache.recentSkipped.join(", ")
            + " — enable Created at in the type's settings in Capacities, then run"
            + "  omarchy-capacities structures --refresh"
          color: root.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
