pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Tailscale (ADR 0058): on or off, sign-in, this machine's name and
// address, the other machines with their addresses, the exit node, and
// Taildrop. A click on a machine copies its address; the send arrow picks
// files for it. Reads the status when it opens and after each action.
PanelBase {
  id: panel

  readonly property var status: Tailscale.status
  readonly property bool running: status !== null && status.running
  readonly property bool signedOut: status !== null && status.needsLogin
  readonly property var peers: running ? status.peers : []
  readonly property int onlineCount: Model.online(status).length
  // A sign-in: asking the helper for the link, then waiting for the browser.
  readonly property bool waitingForBrowser: Tailscale.signingIn && (signedOut || Tailscale.loginUrl !== "")

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  Component.onCompleted: Tailscale.refresh()

  component ActionButton: Button {
    id: control
    height: 30
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
    contentItem: Text {
      text: control.text
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      color: control.enabled ? Theme.text : Theme.muted
      font: control.font
    }
    background: Rectangle {
      radius: 3
      color: control.down ? Theme.selection : Theme.surface
      border.width: 1
      border.color: control.activeFocus ? Theme.accent : Theme.surface
    }
  }

  component Note: Text {
    width: column.width
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    color: Theme.subtext
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Item {
      width: parent.width
      height: 24
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Tailscale: " + Model.stateText(panel.status, Tailscale.daemonDown).replace(/^Tailscale$/, "…")
          + (panel.running && panel.status.tailnet !== "" ? " · " + panel.status.tailnet : "")
        textFormat: Text.PlainText
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      IconButton {
        objectName: "toggle"
        visible: panel.status !== null && !panel.signedOut && !Tailscale.signingIn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Glyphs.tailscale(panel.running)
        color: panel.running ? Theme.accent : Theme.muted
        tooltip: panel.running ? "Turn off" : "Turn on"
        onClicked: panel.running ? Tailscale.down() : Tailscale.up()
      }
    }

    // This machine.
    Rectangle {
      visible: panel.running && panel.status.self.ip !== ""
      width: parent.width
      height: visible ? 36 : 0
      radius: 3
      color: Theme.selection
      Column {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: selfCopy.left
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          text: panel.running ? panel.status.self.name + " (this machine)" : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        Text {
          width: parent.width
          text: panel.running ? [panel.status.self.ip, panel.status.self.dnsName].filter(s => s !== "").join(" · ") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 2
        }
      }
      IconButton {
        id: selfCopy
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Glyphs.copy
        color: Theme.subtext
        tooltip: "Copy the address (right click: the DNS name)"
        onClicked: (mouse) => Tailscale.copy(mouse.button === Qt.RightButton ? panel.status.self.dnsName : panel.status.self.ip)
      }
    }

    // Signed out: the helper prints a link, the browser finishes.
    Note {
      visible: panel.signedOut && !Tailscale.signingIn
      text: "Sign in to join this machine to your tailnet. The sign-in page opens in the browser."
    }
    ActionButton {
      objectName: "signIn"
      visible: panel.signedOut && !Tailscale.signingIn
      width: parent.width
      text: "Sign in"
      onClicked: Tailscale.signIn()
    }
    Note {
      visible: panel.waitingForBrowser
      text: Tailscale.loginUrl !== "" ? "Finish signing in in the browser:\n" + Tailscale.loginUrl : "Asking Tailscale for a sign-in link…"
    }
    Row {
      visible: panel.waitingForBrowser
      spacing: 6
      ActionButton {
        visible: Tailscale.loginUrl !== ""
        width: (column.width - 12) / 3
        text: "Open again"
        onClicked: Tailscale.openLogin()
      }
      ActionButton {
        visible: Tailscale.loginUrl !== ""
        width: (column.width - 12) / 3
        text: "Copy link"
        onClicked: Tailscale.copy(Tailscale.loginUrl)
      }
      ActionButton {
        width: (column.width - 12) / 3
        text: "Cancel"
        onClicked: Tailscale.cancelSignIn()
      }
    }

    Note {
      visible: Tailscale.error !== ""
      text: Tailscale.error
      color: Theme.error
    }

    Note {
      visible: panel.running
      text: panel.onlineCount + " of " + panel.peers.length + (panel.peers.length === 1 ? " machine" : " machines") + " online"
        + (panel.status && panel.status.exitNode ? " · exit node " + panel.status.exitNode.name : "")
    }

    Repeater {
      model: panel.peers.slice(0, 12)
      delegate: Rectangle {
        id: row
        required property var modelData
        width: column.width
        height: 36
        radius: 3
        color: rowMouse.containsMouse ? Theme.surface : "transparent"

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (mouse) => Tailscale.copy(mouse.button === Qt.RightButton ? row.modelData.dnsName : row.modelData.ip)
        }
        Column {
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.right: buttons.left
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: row.modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.modelData.online ? Theme.text : Theme.muted
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            width: parent.width
            text: [row.modelData.ip, row.modelData.online ? "online" : "offline", row.modelData.exitNode ? "exit node" : ""].filter(s => s !== "").join(" · ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 2
          }
        }
        Row {
          id: buttons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          IconButton {
            visible: row.modelData.exitNodeOption
            glyph: Glyphs.tailscale(true)
            color: row.modelData.exitNode ? Theme.accent : Theme.muted
            tooltip: row.modelData.exitNode ? "Stop using it as the exit node" : "Use as exit node (the local network stays reachable)"
            onClicked: Tailscale.setExitNode(row.modelData.exitNode ? null : row.modelData)
          }
          IconButton {
            visible: row.modelData.online && row.modelData.taildrop
            glyph: Glyphs.send
            color: Theme.subtext
            tooltip: "Send files with Taildrop"
            onClicked: {
              Tailscale.send(row.modelData)
              panel.closePanel()
            }
          }
        }
      }
    }

    Note {
      visible: panel.peers.length > 12
      text: (panel.peers.length - 12) + " more, offline or later in the list: tailscale status lists all"
      color: Theme.muted
    }
    Text {
      visible: panel.running
      width: parent.width
      text: "Click copies the address, right click the DNS name. Files sent here land in Downloads."
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
