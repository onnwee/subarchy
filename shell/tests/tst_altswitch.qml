import QtQuick
import QtTest

import "../AltSwitchModel.js" as Model

TestCase {
  name: "AltSwitch"

  function test_orderRecentFirst() {
    const clients = ["a", "b", "c", "d"]
    compare(Model.order(clients, ["c", "a"]), ["c", "a", "b", "d"])
  }

  function test_orderDropsClosedWindows() {
    compare(Model.order(["a", "b"], ["x", "b", "y"]), ["b", "a"])
  }

  function test_remember() {
    compare(Model.remember(["a", "b", "c"], "c", 10), ["c", "a", "b"])
    compare(Model.remember(["a", "b"], "z", 2), ["z", "a"])
    compare(Model.remember(["a"], "", 10), ["a"])
  }

  function test_nextWraps() {
    const order = ["a", "b", "c"]
    compare(Model.next(order, 0, 1), 1)
    compare(Model.next(order, 2, 1), 0)
    compare(Model.next(order, 0, -1), 2)
    compare(Model.next([], 0, 1), -1)
  }

  function test_startsOnPrevious() {
    compare(Model.start(["a", "b", "c"], 1), 1, "Alt-Tab starts on the window used before this one")
    compare(Model.start(["a"], 1), 0)
    compare(Model.start(["a", "b"], -1), 1, "Alt-Shift-Tab starts on the oldest")
  }

  function test_focusRank() {
    verify(Model.focusRank({ focusHistoryID: 0 }) < Model.focusRank({ focusHistoryID: 1 }), "the focused window first")
    verify(Model.focusRank({ focusHistoryID: 3 }) < Model.focusRank(undefined), "no IPC object: last")
    verify(Model.focusRank({ focusHistoryID: 3 }) < Model.focusRank({ focusHistoryID: -1 }), "-1: last")
    verify(Model.focusRank({ focusHistoryID: 3 }) < Model.focusRank({}), "missing: last")
  }

  function test_byFocus() {
    const tops = [
      { address: "a", lastIpcObject: { focusHistoryID: 1 } },
      { address: "none" },
      { address: "b", lastIpcObject: { focusHistoryID: 0 } },
      { address: "c", lastIpcObject: { focusHistoryID: 2 } }
    ]
    compare(Model.byFocus(tops), ["b", "a", "c", "none"], "focused first, no IPC object last")
    compare(tops[0].address, "a", "the input is not reordered")
    compare(Model.byFocus([]), [])
  }

  // A window opened since the last client list has no IPC object yet; its
  // Wayland app id names it.
  function test_appClass() {
    compare(Model.appClass({ class: "kitty" }, "kitty-wl"), "kitty", "Hyprland's class first")
    compare(Model.appClass(undefined, "org.gnome.Nautilus"), "org.gnome.Nautilus", "a new window")
    compare(Model.appClass({ class: "" }, "firefox"), "firefox")
    compare(Model.appClass(null, ""), "")
    compare(Model.appClass(null, undefined), "")
  }

  // After a shell start the history is empty; Hyprland's focus history
  // orders the clients, so Alt-Tab picks the window used before.
  function test_startsOnPreviousWithEmptyHistory() {
    const tops = [{ address: "a", lastIpcObject: { focusHistoryID: 1 } }, { address: "b", lastIpcObject: { focusHistoryID: 0 } }]
    const order = Model.order(Model.byFocus(tops), [])
    compare(order[Model.start(order, 1)], "a")
  }
}
