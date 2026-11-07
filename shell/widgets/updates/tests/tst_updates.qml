import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Updates"

  function test_count() {
    compare(Model.count("12\n"), 12)
    compare(Model.count(""), 0)
    compare(Model.count("oops"), 0)
    compare(Model.count("-3"), 0)
  }

  function test_updatesHiddenAtZero() {
    verify(Model.hidden(0))
    verify(!Model.hidden(4))
  }
}
