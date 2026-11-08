import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Network"

  readonly property var home: ({ name: "Home", signalStrength: 0.8, security: 3, connected: true, known: true, state: 2 })
  readonly property var homeWeak: ({ name: "Home", signalStrength: 0.3, security: 3, connected: false, known: true, state: 4 })
  readonly property var cafe: ({ name: "Cafe", signalStrength: 0.9, security: 10, connected: false, known: false, state: 4 })
  readonly property var work: ({ name: "Work", signalStrength: 0.5, security: 2, connected: false, known: true, state: 4 })
  readonly property var secret: ({ name: "Neighbour", signalStrength: 0.95, security: 3, connected: false, known: false, state: 4 })
  readonly property var hidden: ({ name: "", signalStrength: 0.99, security: 3, connected: false, known: false, state: 4 })

  function test_sort() {
    const out = Model.sortNetworks([secret, cafe, homeWeak, work, home, hidden, null])
    compare(out.map(n => n.name), ["Home", "Work", "Neighbour", "Cafe"], "connected, known, then signal")
    compare(out[0].signalStrength, 0.8, "the connected access point wins over a stronger one of the same name")
    compare(Model.sortNetworks([]), [])
  }

  function test_rules() {
    verify(Model.joinable(home))
    verify(Model.joinable(cafe), "open")
    verify(!Model.joinable(secret), "a new WPA2 network needs a password")
    verify(Model.needsPassword(secret))
    verify(!Model.needsPassword(home), "known networks have their secret")
    verify(!Model.needsPassword(cafe))
    verify(!Model.needsPassword({ name: "x", security: 2, known: false }), "enterprise networks are not a password prompt")
    compare(Model.securityText(3), "WPA2")
    compare(Model.securityText(10), "Open")
    compare(Model.securityText(99), "Unknown")
    compare(Model.stateText(home), "Connected")
    compare(Model.stateText(work), "Saved")
    compare(Model.stateText(cafe), "")
    compare(Model.stateText({ state: 1 }), "Connecting…")
    compare(Model.signalText(0.734), "73 %")
    compare(Model.signalText(60), "60 %")
  }
}
