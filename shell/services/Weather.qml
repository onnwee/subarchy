pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/weather/Model.js" as Model

// Weather data, shared by the bar widget and its panel. Current conditions
// come from Open-Meteo, the forecast, sun, moon and tides from `linecast
// --json` (its own package). Nothing is fetched until a location is set;
// the widget's manifest timers decide when, the panel asks again when what
// it shows is older than the AC interval.
Singleton {
  id: root

  property var location: null // { lat, lon }
  property bool imperial: false
  property var current: null
  property double currentAt: 0
  property var almanac: null // { forecast, sun, moon, tides }
  property double almanacAt: 0
  property string error: ""
  property string almanacError: ""
  property var matches: []
  property bool searching: false
  property string searchError: ""

  function configure(settings) {
    const loc = Model.location(settings)
    const imp = Model.imperial(settings)
    const changed = JSON.stringify(loc) !== JSON.stringify(root.location) || imp !== root.imperial
    root.location = loc
    root.imperial = imp
    if (changed) {
      root.current = null
      root.currentAt = 0
      root.almanac = null
      root.almanacAt = 0
      root.refreshCurrent()
      root.refreshAlmanac()
    }
  }

  function refreshCurrent() {
    if (!root.location || currentQuery.running)
      return
    currentQuery.command = Model.currentCommand(root.location, root.imperial)
    currentQuery.running = true
  }

  function refreshAlmanac() {
    if (!root.location || almanacQuery.running)
      return
    almanacQuery.command = Model.almanacCommand(root.location, root.imperial)
    almanacQuery.running = true
  }

  // The panel opening: refresh what is older than the AC interval.
  function refreshStale(currentMaxMs, almanacMaxMs) {
    const now = Date.now()
    if (Model.stale(root.currentAt, currentMaxMs, now))
      root.refreshCurrent()
    if (Model.stale(root.almanacAt, almanacMaxMs, now))
      root.refreshAlmanac()
  }

  function search(query) {
    if (String(query).trim() === "" || searchQuery.running)
      return
    root.matches = []
    root.searchError = ""
    root.searching = true
    searchQuery.command = Model.searchCommand(query.trim())
    searchQuery.running = true
  }

  // The panel closing: its matches do not outlive it.
  function clearMatches() {
    root.matches = []
    root.searchError = ""
  }

  Process {
    id: currentQuery
    stdout: StdioCollector {
      onStreamFinished: {
        const c = Model.parseCurrent(text)
        if (c) {
          root.current = c
          root.currentAt = Date.now()
          root.error = ""
        }
      }
    }
    onExited: (code) => {
      if (code !== 0)
        root.error = "Open-Meteo did not answer"
    }
  }

  Process {
    id: almanacQuery
    stdout: StdioCollector {
      onStreamFinished: {
        const a = Model.parseAlmanac(text)
        if (Model.almanacHasData(a)) {
          root.almanac = a
          root.almanacAt = Date.now()
          root.almanacError = ""
        } else {
          // Nothing came through: linecast is missing or every part failed.
          // almanacAt stays, so the next panel opening tries again.
          root.almanacError = "linecast gave no forecast (is it installed?)"
        }
      }
    }
    onExited: (code) => {
      if (code !== 0)
        root.almanacError = "linecast gave no forecast (is it installed?)"
    }
  }

  Process {
    id: searchQuery
    stdout: StdioCollector {
      onStreamFinished: {
        root.matches = Model.parseSearch(text)
        if (root.matches.length === 0)
          root.searchError = "No place found"
      }
    }
    onExited: (code) => {
      root.searching = false
      if (code !== 0)
        root.searchError = "linecast did not answer (is it installed?)"
    }
  }

  IpcHandler {
    target: "subcult.weather"
    function search(query: string): void { root.search(query) }
    function state(): string {
      return JSON.stringify({
        location: root.location, current: root.current, error: root.error, almanacError: root.almanacError, searchError: root.searchError,
        almanac: root.almanac ? Object.keys(root.almanac).filter(k => root.almanac[k] !== null) : [],
        matches: root.matches
      })
    }
  }
}
