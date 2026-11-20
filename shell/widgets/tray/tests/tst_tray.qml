import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Tray"

  readonly property int passiveStatus: 0
  readonly property int leftButton: 1
  readonly property int rightButton: 2
  readonly property int middleButton: 4

  function test_passiveItemsAreHidden() {
    const items = [{ id: "a", status: 0 }, { id: "b", status: 1 }, { id: "c", status: 2 }]
    compare(Model.visible(items, passiveStatus).map(i => i.id), ["b", "c"])
  }

  function test_noItems() {
    compare(Model.visible([], passiveStatus), [])
    compare(Model.visible(null, passiveStatus), [])
  }

  function test_rightClickOpensMenu() {
    compare(Model.action({ hasMenu: true, onlyMenu: false }, rightButton), "menu")
  }

  function test_rightClickWithoutMenuActivates() {
    compare(Model.action({ hasMenu: false, onlyMenu: false }, rightButton), "activate")
  }

  function test_leftClickOnMenuOnlyItemOpensMenu() {
    compare(Model.action({ hasMenu: true, onlyMenu: true }, leftButton), "menu")
  }

  function test_leftClickActivates() {
    compare(Model.action({ hasMenu: true, onlyMenu: false }, leftButton), "activate")
  }

  function test_middleClickIsSecondary() {
    compare(Model.action({ hasMenu: true, onlyMenu: true }, middleButton), "secondary")
    compare(Model.action({ hasMenu: false, onlyMenu: false }, middleButton), "secondary")
  }
}
