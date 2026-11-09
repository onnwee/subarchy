import QtQuick
import Quickshell
import "LockModel.js" as Model

// One output's lock surface: the lockup and the clock in the middle, the
// prompt under them once a key was pressed. Keys go to the program through
// `key`; the text typed never shows, only bullets.
FocusScope {
  id: view

  property var lockState: Model.initial()
  // The shell's colour tokens (base, text, subtext, muted, surface, border, error).
  property var theme: ({})

  signal key(string name, string text)

  focus: true
  Keys.onPressed: (event) => {
    view.key(Model.keyName(event.key), event.text)
    event.accepted = true
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Column {
    anchors.centerIn: parent
    spacing: 28

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 360
      source: Qt.resolvedUrl("lockup-dark.svg")
      sourceSize.width: 360
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Model.clockText(clock.date)
      color: view.theme.text || "#F0ECE4"
      font.family: "monospace"
      font.pixelSize: 64
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(clock.date, "dddd d MMMM")
      color: view.theme.subtext || "#9A92A8"
      font.family: "sans-serif"
      font.pixelSize: 18
    }

    Item {
      width: 320
      height: 72
      anchors.horizontalCenter: parent.horizontalCenter

      Rectangle {
        id: field
        visible: view.lockState.prompt
        width: parent.width
        height: 40
        color: view.theme.surface || "#1F1830"
        border.width: 1
        border.color: view.lockState.checking ? (view.theme.muted || "#5E5570") : (view.theme.border || "#8F4BC8")

        Text {
          anchors.centerIn: parent
          text: view.lockState.checking ? "Checking…" : Model.bullets(view.lockState.password.length)
          color: view.theme.text || "#F0ECE4"
          font.family: "monospace"
          font.pixelSize: 18
        }
      }

      Text {
        anchors.top: field.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        visible: view.lockState.prompt && view.lockState.message !== ""
        text: view.lockState.message
        color: view.theme.error || "#D52032"
        font.family: "sans-serif"
        font.pixelSize: 14
      }

      Text {
        anchors.centerIn: parent
        visible: !view.lockState.prompt
        text: "Press a key to unlock"
        color: view.theme.muted || "#5E5570"
        font.family: "sans-serif"
        font.pixelSize: 14
      }
    }
  }
}
