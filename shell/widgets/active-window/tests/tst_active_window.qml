import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "ActiveWindow"

  function test_titleOfFocusedWindow() {
    compare(Model.title({ title: "notes - Obsidian" }), "notes - Obsidian")
  }

  function test_emptyWithoutFocus() {
    compare(Model.title(null), "")
    compare(Model.title(undefined), "")
  }

  function test_nonStringTitleIsEmpty() {
    compare(Model.title({ title: undefined }), "")
    compare(Model.title({ title: 5 }), "")
  }
}
