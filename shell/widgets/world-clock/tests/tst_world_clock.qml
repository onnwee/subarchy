import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "WorldClock"

  // 2026-11-07 12:00 UTC
  readonly property real noon: Date.UTC(2026, 10, 7, 12, 0, 0)

  function test_formatZone() {
    compare(Model.formatAt(noon, 540, "Tokyo"), "Tokyo 21:00")
    compare(Model.formatAt(noon, -360, "Chicago"), "Chicago 06:00")
    compare(Model.formatAt(noon, 330, "Delhi"), "Delhi 17:30")
  }

  function test_formatWrapsDays() {
    compare(Model.formatAt(Date.UTC(2026, 10, 7, 23, 30), 120, "Kyiv"), "Kyiv 01:30")
  }

  function test_parseOffset() {
    compare(Model.parseOffset("+0900"), 540)
    compare(Model.parseOffset("-0600"), -360)
    compare(Model.parseOffset("+0530"), 330)
    compare(Model.parseOffset("junk"), null)
  }

  function test_label() {
    compare(Model.label("Asia/Tokyo"), "Tokyo")
    compare(Model.label("America/Argentina/Buenos_Aires"), "Buenos Aires")
  }
}
