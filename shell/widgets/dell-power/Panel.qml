pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model

// The Dell firmware profiles (quiet, cool, balanced, performance), the
// charging mode (adaptive, standard, express, primarily AC, custom) and the
// custom thresholds with their step buttons; Apply writes the thresholds.
// Opening the panel reads the state again.
PanelBase {
  id: panel

  readonly property var report: DellPower.report
  readonly property var custom: Model.custom(report)
  readonly property string mode: Model.activeId(Model.modes(report))
  property int start: 0
  property int stop: 0

  implicitWidth: 320
  implicitHeight: column.implicitHeight

  Component.onCompleted: {
    DellPower.refresh()
    panel.reset()
  }
  onCustomChanged: reset()

  function reset() {
    if (panel.custom) {
      panel.start = Number(panel.custom.start)
      panel.stop = Number(panel.custom.stop)
    }
  }

  function step(which, direction) {
    const next = Model.stepped(panel.custom, panel.start, panel.stop, which, direction)
    panel.start = next.start
    panel.stop = next.stop
  }

  component Choice: Rectangle {
    id: choice
    required property var modelData
    property bool active: false
    signal pick(string id)
    width: 96
    height: 28
    radius: 3
    color: active ? Theme.selection : Theme.base
    border.width: 1
    border.color: active ? Theme.accent : Theme.surface
    Text {
      anchors.centerIn: parent
      text: choice.modelData.name
      color: choice.active ? Theme.text : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
    MouseArea {
      anchors.fill: parent
      enabled: !DellPower.busy
      onClicked: choice.pick(choice.modelData.id)
    }
  }

  component Heading: Text {
    color: Theme.subtext
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
    font.bold: true
  }

  component StepButton: Rectangle {
    id: stepButton
    property string glyph: "+"
    signal pressed()
    width: 26
    height: 26
    radius: 3
    color: Theme.base
    border.width: 1
    border.color: Theme.surface
    Text {
      anchors.centerIn: parent
      text: stepButton.glyph
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    MouseArea {
      anchors.fill: parent
      enabled: !DellPower.busy
      onClicked: stepButton.pressed()
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 8

    Heading { text: "Dell power profile" }

    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: Model.profiles(panel.report)
        delegate: Choice {
          active: modelData.active
          onPick: (id) => DellPower.setProfile(id)
        }
      }
    }

    Text {
      width: parent.width
      text: "Quiet and cool run the daemon's power saver, balanced and performance their own."
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }

    Rectangle {
      visible: Model.modes(panel.report).length > 0
      width: parent.width
      height: 1
      color: Theme.surface
    }

    Heading {
      visible: Model.modes(panel.report).length > 0
      text: "Charging"
    }

    Flow {
      visible: Model.modes(panel.report).length > 0
      width: parent.width
      spacing: 6
      Repeater {
        model: Model.modes(panel.report)
        delegate: Choice {
          active: modelData.active
          onPick: (id) => id === "custom" && panel.custom ? DellPower.setCharging(id, panel.start, panel.stop) : DellPower.setCharging(id)
        }
      }
    }

    Row {
      visible: panel.mode === "custom" && panel.custom !== null
      spacing: 8
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Charge from"
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
      StepButton { glyph: "−"; onPressed: panel.step("start", -1) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        horizontalAlignment: Text.AlignHCenter
        text: panel.start + " %"
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      StepButton { glyph: "+"; onPressed: panel.step("start", 1) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "to"
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
      StepButton { glyph: "−"; onPressed: panel.step("stop", -1) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        horizontalAlignment: Text.AlignHCenter
        text: panel.stop + " %"
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      StepButton { glyph: "+"; onPressed: panel.step("stop", 1) }
    }

    Rectangle {
      id: apply
      visible: panel.mode === "custom" && panel.custom !== null
        && (panel.start !== Number(panel.custom.start) || panel.stop !== Number(panel.custom.stop))
      width: 96
      height: 28
      radius: 3
      color: Theme.selection
      border.width: 1
      border.color: Theme.accent
      Text {
        anchors.centerIn: parent
        text: DellPower.busy ? "Applying" : "Apply"
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
      MouseArea {
        anchors.fill: parent
        enabled: !DellPower.busy
        onClicked: DellPower.setCharging("custom", panel.start, panel.stop)
      }
    }

    Text {
      visible: DellPower.error !== ""
      width: parent.width
      text: DellPower.error
      wrapMode: Text.Wrap
      color: Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
  }
}
