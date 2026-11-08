import QtQuick
import QtTest

import "../PolkitModel.js" as Model

TestCase {
  name: "Polkit"

  function test_pickIdentity() {
    compare(Model.pickIdentity([{ name: "root" }, { name: "onnwee" }], "onnwee"), 1, "the current user, second")
    compare(Model.pickIdentity([{ name: "root" }, { name: "admin" }], "onnwee"), 0, "absent: the first")
    compare(Model.pickIdentity([], "onnwee"), 0, "empty")
    compare(Model.pickIdentity(null, "onnwee"), 0)
    compare(Model.pickIdentity([{ name: "root" }], ""), 0)
  }
}
