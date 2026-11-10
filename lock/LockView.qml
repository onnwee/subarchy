pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtMultimedia
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

  property bool animate: false
  property url video: ""
  property url still: ""

  signal key(string name, string text)
  signal wake()
  signal playbackChanged(bool active)

  focus: true
  activeFocusOnTab: true
  Component.onCompleted: view.forceActiveFocus()
  Window.onActiveChanged: {
    if (Window.active)
      view.forceActiveFocus(Qt.ActiveWindowFocusReason)
  }
  Keys.onPressed: (event) => {
    view.key(Model.keyName(event.key), event.text)
    event.accepted = true
  }

  Image {
    anchors.fill: parent
    visible: !view.lockState.prompt
    source: view.still
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  // Destroy the decoder as soon as input opens the prompt or motion stops.
  Loader {
    anchors.fill: parent
    active: !view.lockState.prompt && view.animate && view.video.toString() !== ""
    sourceComponent: Video {
      source: view.video
      autoPlay: true
      loops: MediaPlayer.Infinite
      fillMode: VideoOutput.PreserveAspectFit
      muted: true
      property bool reported: false
      onPlaybackStateChanged: {
        const active = playbackState === MediaPlayer.PlayingState
        if (active !== reported) {
          reported = active
          view.playbackChanged(active)
        }
      }
      Component.onDestruction: { if (reported) view.playbackChanged(false) }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    // The initial enter isn't input; wait for a position change after it.
    property bool havePosition: false
    onEntered: havePosition = false
    onPositionChanged: {
      if (havePosition) view.wake()
      havePosition = true
    }
    onPressed: {
      view.forceActiveFocus(Qt.MouseFocusReason)
      view.wake()
    }
    onWheel: view.wake()
  }

  // A timer of its own, not SystemClock: that one re-arms every millisecond
  // through the hour that repeats when daylight saving ends (#54 removed it
  // from the shell for the same reason).
  property date now: new Date()
  Timer {
    interval: Model.nextTickMs(Date.now())
    running: true
    repeat: true
    onTriggered: {
      view.now = new Date()
      interval = Model.nextTickMs(view.now.getTime())
    }
  }

  Column {
    visible: view.lockState.prompt || view.still.toString() === ""
    anchors.centerIn: parent
    spacing: 28

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 360
      height: width * 0.26
      source: Qt.resolvedUrl("lockup-dark.png")
      sourceSize.width: width * 2
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Model.clockText(view.now)
      color: view.theme.text || "#F0ECE4"
      font.family: "monospace"
      font.pixelSize: 64
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(view.now, "dddd d MMMM")
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
        border.color: view.lockState.checking ? (view.theme.muted || "#5E5570")
          : view.activeFocus ? (view.theme.accent || "#8B5CF6") : (view.theme.border || "#8F4BC8")

        Text {
          anchors.centerIn: parent
          text: view.lockState.checking ? "Checking…" : view.lockState.password.length > 0 ? Model.bullets(view.lockState.password.length) : "Password"
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
