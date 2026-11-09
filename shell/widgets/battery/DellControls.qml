pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.services
import "../dell-power/Model.js" as Model

// The Dell firmware profiles (quiet, cool, balanced, performance), the
// charging mode (adaptive, standard, express, primarily AC, custom) and the
// custom thresholds with their step buttons; Apply writes the thresholds.
// Opening the panel reads the state again.
Item {
  id: panel

  readonly property var report: DellPower.report
  readonly property var custom: Model.custom(report)
  readonly property string mode: Model.activeId(Model.modes(report))
  property int start: 0
  property int stop: 0

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  Component.onCompleted: panel.reset()
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

  component Heading: Text {
    color: Theme.subtext
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
    font.bold: true
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
          required property var modelData
          objectName: "dellProfile_" + modelData.id
          label: modelData.name
          active: modelData.active
          enabled: !DellPower.busy
          onPicked: DellPower.setProfile(modelData.id)
        }
      }
    }

    Text {
      width: parent.width
      text: "Quiet and Cool use power saver. Balanced and Performance use their matching power modes."
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
          required property var modelData
          objectName: "chargingMode_" + modelData.id
          label: modelData.name
          active: modelData.active
          enabled: !DellPower.busy
          onPicked: modelData.id === "custom" && panel.custom ? DellPower.setCharging(modelData.id, panel.start, panel.stop) : DellPower.setCharging(modelData.id)
        }
      }
    }

    Column {
      objectName: "customThresholds"
      visible: panel.mode === "custom" && panel.custom !== null
      width: parent.width
      spacing: 6
      Repeater {
        model: ["start", "stop"]
        delegate: Row {
          id: threshold
          required property string modelData
          spacing: 8
          Text {
            width: 148
            anchors.verticalCenter: parent.verticalCenter
            text: threshold.modelData === "start" ? "Start charging below" : "Stop charging at"
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
          Choice {
            objectName: threshold.modelData + "Decrease"
            label: "−"
            checkable: false
            Accessible.name: "Decrease charge " + threshold.modelData
            enabled: !DellPower.busy
            onPicked: panel.step(threshold.modelData, -1)
          }
          Text {
            width: 38
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: (threshold.modelData === "start" ? panel.start : panel.stop) + " %"
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Choice {
            objectName: threshold.modelData + "Increase"
            label: "+"
            checkable: false
            Accessible.name: "Increase charge " + threshold.modelData
            enabled: !DellPower.busy
            onPicked: panel.step(threshold.modelData, 1)
          }
        }
      }
      Choice {
        objectName: "applyThresholds"
        label: DellPower.busy ? "Applying…" : "Apply thresholds"
        checkable: false
        active: true
        enabled: !DellPower.busy && panel.custom !== null
          && (panel.start !== Number(panel.custom.start) || panel.stop !== Number(panel.custom.stop))
        onPicked: DellPower.setCharging("custom", panel.start, panel.stop)
      }
    }

    Text {
      objectName: "chargingUnavailable"
      visible: Model.modes(panel.report).length === 0
      width: parent.width
      text: "Charging controls are unavailable. If this laptop supports charge limits, check the Dell charging-control permission service."
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
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
