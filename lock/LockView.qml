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
  // The loop could not be played (a missing or broken file).
  property bool videoFailed: false

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

  // The still is the effect's last frame: shown in place of the loop (on
  // battery, with motion off, or when the video fails), never under it,
  // where it flashed before the first decoded frame.
  Image {
    objectName: "lockStill"
    anchors.fill: parent
    visible: !view.lockState.prompt && (!motionArt.active || view.videoFailed)
    source: view.still
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  // Destroy the decoder as soon as input opens the prompt or motion stops.
  Loader {
    id: motionArt
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
      onSourceChanged: view.videoFailed = false
      onErrorOccurred: view.videoFailed = true
      Component.onDestruction: {
        view.videoFailed = false
        if (reported) view.playbackChanged(false)
      }
    }
  }

  MouseArea {
    objectName: "lockPointer"
    anchors.fill: parent
    hoverEnabled: true
    // The lock has nothing to point at; the pointer stayed over the clock.
    cursorShape: Qt.BlankCursor
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

      // The field looks like the disk unlock prompt at boot
      // (default/plymouth): a surface-coloured box with a violet edge, a
      // lock on its left, and one round bullet per character from the left.
      Rectangle {
        id: field
        visible: view.lockState.prompt
        width: parent.width
        height: 36
        color: view.theme.surface || "#1F1830"
        border.width: 1
        border.color: view.lockState.checking ? (view.theme.muted || "#5E5570") : (view.theme.border || "#8B5CF6")

        Row {
          visible: !view.lockState.checking
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Repeater {
            model: Model.bulletCount(view.lockState.password.length)
            Rectangle {
              width: 12
              height: 12
              radius: 6
              color: view.theme.accent || "#00FF88"
            }
          }
        }

        Text {
          visible: view.lockState.checking
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: "Checking…"
          color: view.theme.muted || "#5E5570"
          font.family: "sans-serif"
          font.pixelSize: 14
        }
      }

      // The lock: a shackle behind a body with a keyhole.
      Item {
        visible: view.lockState.prompt
        width: 20
        height: 26
        anchors.right: field.left
        anchors.rightMargin: 14
        anchors.verticalCenter: field.verticalCenter
        Rectangle {
          x: 4
          y: 1
          width: 12
          height: 18
          radius: 6
          color: "transparent"
          border.width: 2
          border.color: view.theme.text || "#F0ECE4"
        }
        Rectangle {
          x: 2
          y: 11
          width: 16
          height: 13
          color: view.theme.text || "#F0ECE4"
        }
        Rectangle {
          x: 9
          y: 15
          width: 2
          height: 5
          color: view.theme.base || "#100B19"
        }
      }

      Text {
        anchors.top: field.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        visible: view.lockState.prompt && view.lockState.message !== ""
        text: view.lockState.message
        width: Math.min(implicitWidth, view.width - 48)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        // While a check runs this is what PAM says ("Place your finger…").
        color: view.lockState.checking ? (view.theme.muted || "#5E5570") : (view.theme.error || "#D52032")
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
