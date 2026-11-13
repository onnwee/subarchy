import QtQuick
import QtTest

import "../PolkitModel.js" as Model

TestCase {
  name: "Polkit"

  // Fixtures follow Quickshell's polkit Identity: the user or group name is
  // in `string`, and `isGroup` tells the two apart.
  function user(name) { return { string: name, displayName: name, isGroup: false } }
  function group(name) { return { string: name, displayName: name, isGroup: true } }

  function test_pickIdentity() {
    compare(Model.pickIdentity([user("root"), user("onnwee")], "onnwee"), 1, "the current user, second")
    compare(Model.pickIdentity([user("root"), user("admin")], "onnwee"), 0, "absent: the first")
    compare(Model.pickIdentity([], "onnwee"), 0, "empty")
    compare(Model.pickIdentity(null, "onnwee"), 0)
    compare(Model.pickIdentity([user("root")], ""), 0)
  }

  function test_groupWithTheUsersName() {
    compare(Model.pickIdentity([group("onnwee"), user("root"), user("onnwee")], "onnwee"), 2,
            "a group named like the user is not the user")
    compare(Model.pickIdentity([group("onnwee"), user("root")], "onnwee"), 0, "only a group: the first")
  }
}
