pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model

// The place and a search box to change it, the conditions now, the week's
// forecast, then sun, moon and tides. Opening it refreshes what is older
// than the AC interval. Exists only while open.
PanelBase {
  id: panel

  readonly property var current: Weather.current
  readonly property var forecast: Weather.almanac ? Weather.almanac.forecast : null
  readonly property var sun: Weather.almanac ? Weather.almanac.sun : null
  readonly property var moon: Weather.almanac ? Weather.almanac.moon : null
  readonly property var tides: Weather.almanac ? Weather.almanac.tides : null
  readonly property string name: String(settings.name || "")

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  // Stale means older than the AC interval the manifest declares.
  Component.onCompleted: Weather.refreshStale(Model.timerMs(panel.shell.manifest, "current", 900000), Model.timerMs(panel.shell.manifest, "almanac", 7200000))
  Component.onDestruction: Weather.clearMatches()

  function choose(match) {
    if (panel.shell.config) {
      panel.shell.config.set("location", match.location)
      panel.shell.config.set("name", match.name)
    }
    Weather.matches = []
    search.text = ""
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Text {
      width: parent.width
      text: panel.name !== "" ? panel.name : (Weather.location ? Weather.location.lat + ", " + Weather.location.lon : "No location yet")
      elide: Text.ElideRight
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
      font.bold: true
    }

    Rectangle {
      width: parent.width
      height: 24
      radius: 3
      color: Theme.surface
      TextInput {
        id: search
        anchors.fill: parent
        anchors.margins: 4
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
        focus: true
        onAccepted: Weather.search(text)
        Text {
          visible: search.text === ""
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: Weather.location ? "Change the place: type it, then Enter" : "Type a place, then Enter"
          color: Theme.muted
          font: search.font
        }
      }
    }
    Text {
      visible: Weather.searching || Weather.searchError !== ""
      text: Weather.searching ? "Searching…" : Weather.searchError
      color: Weather.searching ? Theme.muted : Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
    Repeater {
      model: Weather.matches.slice(0, 6)
      delegate: Rectangle {
        id: match
        required property var modelData
        width: column.width
        height: 22
        radius: 3
        color: area.containsMouse ? Theme.selection : "transparent"
        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: 6
          width: parent.width - 12
          text: match.modelData.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          onClicked: panel.choose(match.modelData)
        }
      }
    }

    Text {
      visible: Weather.location !== null && (Weather.error !== "" || Weather.almanacError !== "")
      width: parent.width
      text: [Weather.error, Weather.almanacError].filter(e => e !== "").join("\n")
      wrapMode: Text.Wrap
      color: Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Row {
      visible: panel.current !== null
      width: parent.width
      spacing: 10
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: panel.current ? Model.glyph(panel.current.code, panel.current.isDay) : ""
        color: Theme.text
        font.family: Style.fontFamily
        font.pixelSize: 28
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: panel.current ? Model.degrees(panel.current.temp) + " " + Model.condition(panel.current.code) : ""
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 3
        }
        Text {
          text: panel.current ? "Feels " + Model.degrees(panel.current.feels) + " · humidity " + Math.round(panel.current.humidity) + "% · wind "
            + Math.round(panel.current.wind) + " " + panel.current.windUnit : ""
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }

    Rectangle {
      visible: panel.forecast !== null
      width: parent.width
      height: 1
      color: Theme.surface
    }
    Repeater {
      model: panel.forecast && Array.isArray(panel.forecast.daily) ? panel.forecast.daily.slice(0, 7) : []
      delegate: Row {
        id: day
        required property var modelData
        required property int index
        width: column.width
        height: 20
        spacing: 8
        Text {
          width: 48
          anchors.verticalCenter: parent.verticalCenter
          text: Model.dayName(day.modelData.date, day.index)
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        Text {
          width: 20
          anchors.verticalCenter: parent.verticalCenter
          text: Model.glyph(day.modelData.weather_code, true)
          color: Theme.text
          font.family: Style.fontFamily
          font.pixelSize: Style.iconSize
        }
        Text {
          width: 90
          anchors.verticalCenter: parent.verticalCenter
          text: Model.degrees(day.modelData.high) + " / " + Model.degrees(day.modelData.low)
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: (Number(day.modelData.precipitation_probability) > 0 ? day.modelData.precipitation_probability + "% " : "") + String(day.modelData.condition || "")
          textFormat: Text.PlainText
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }

    Rectangle {
      visible: panel.sun !== null || panel.moon !== null || panel.tides !== null
      width: parent.width
      height: 1
      color: Theme.surface
    }
    Text {
      visible: panel.sun !== null
      width: parent.width
      text: panel.sun ? "\u{F059C} " + Model.clock(panel.sun.sunrise) + "   \u{F059B} " + Model.clock(panel.sun.sunset)
        + "   day " + Model.duration(panel.sun.day_length_seconds) : ""
      color: Theme.subtext
      font.family: Style.fontFamily
      font.pixelSize: Style.fontSize - 1
    }
    Text {
      visible: panel.moon !== null
      width: parent.width
      text: panel.moon ? String(panel.moon.icon || "") + " " + String(panel.moon.phase || "") + ", " + Math.round(Number(panel.moon.illumination) || 0) + "% lit"
        + (Array.isArray(panel.moon.events) ? panel.moon.events.slice(0, 2).map(e => "   " + (e.kind === "rise" ? "↑" : "↓") + Model.clock(e.time)).join("") : "")
        + (panel.moon.next_full ? "   full " + String(panel.moon.next_full).slice(5) : "") : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.fontFamily
      font.pixelSize: Style.fontSize - 1
    }
    Text {
      visible: panel.tides !== null
      width: parent.width
      text: {
        if (!panel.tides)
          return ""
        const next = Model.nextTides(panel.tides, Clock.now, 3)
        if (next.length === 0)
          return "Tides: no station nearby"
        const unit = panel.tides.units && panel.tides.units.height ? " " + panel.tides.units.height : ""
        return "Tides " + next.map(e => (e.kind === "high" ? "▲" : "▼") + Model.clock(e.time) + " " + Number(e.height).toFixed(1) + unit).join("  ")
          + (panel.tides.station ? "  · " + panel.tides.station : "")
      }
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.fontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Text {
      visible: Weather.location !== null
      width: parent.width
      text: "Now: Open-Meteo" + (Weather.currentAt ? " " + Qt.formatDateTime(new Date(Weather.currentAt), "hh:mm") : "")
        + " · forecast, sun, moon, tides: linecast" + (Weather.almanacAt ? " " + Qt.formatDateTime(new Date(Weather.almanacAt), "hh:mm") : (panel.forecast === null ? " (loading)" : ""))
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
