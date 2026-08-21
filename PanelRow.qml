import QtQuick
import qs.Commons

// One clickable line in the panel: a label that gets the space, an optional
// trailing note (a date, an age) that never gets squeezed, and a hover
// highlight. Rows are places — activating one opens it in Capacities.
Item {
  id: root

  property string label: ""
  property string trailing: ""
  property int indent: 0
  property color foreground: Color.popups.text
  property color hoverBackground: Color.menu.selectedBackground

  signal activated()

  implicitHeight: Math.max(Style.space(22), labelText.implicitHeight + Style.space(6))
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Style.space(5)
    color: hover.hovered ? root.hoverBackground : "transparent"
  }

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6) + root.indent * Style.space(12)
    anchors.right: trailingText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    // Captured text is text, never markup: under AutoText a line like
    // "<div> needs margin" renders as empty and the row looks broken.
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.foreground
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: trailingText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    text: root.trailing
    color: Qt.darker(root.foreground, 1.6)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }

  HoverHandler { id: hover }

  TapHandler {
    onTapped: root.activated()
  }
}
