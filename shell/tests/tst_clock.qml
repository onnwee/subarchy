import QtQuick
import QtTest

import "../Commons/ClockModel.js" as Model

TestCase {
  name: "Clock"

  // 2026-11-07T19:00:00Z
  readonly property real minute: 1794164400000

  function test_nextDelay() {
    compare(Model.nextDelayMs(minute - 10), 60, "at :59.990 the next minute is 10 ms away, plus 50 ms slack")
    compare(Model.nextDelayMs(minute), 60050, "at a whole minute the next one is a full minute away")
    compare(Model.nextDelayMs(minute + 30000), 30050)
  }

  function test_neverNegative() {
    verify(Model.nextDelayMs(minute - 3600000) >= 50, "an hour earlier than a previous tick")
    verify(Model.nextDelayMs(minute - 1) >= 50)
    verify(Model.nextDelayMs(-5) >= 50)
    verify(Model.nextDelayMs(NaN) >= 50 && Model.nextDelayMs(NaN) <= 60050)
    for (let i = 0; i < 1000; i++) {
      const d = Model.nextDelayMs(minute + Math.floor(Math.random() * 3600000))
      verify(d >= 50 && d <= 60050, "delay out of range: " + d)
    }
  }
}
