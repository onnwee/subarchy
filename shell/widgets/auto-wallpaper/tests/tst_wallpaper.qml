import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "AutoWallpaper"

  function test_images() {
    compare(Model.images(["b.png", "a.jpg", "notes.txt", "c.JPEG", "d.webp", ".hidden.png"]), [".hidden.png", "a.jpg", "b.png", "c.JPEG", "d.webp"])
    compare(Model.images(null), [])
  }

  function test_sequential() {
    const l = ["a.png", "b.png", "c.png"]
    compare(Model.next(l, "a.png", "sequential"), "b.png")
    compare(Model.next(l, "c.png", "sequential"), "a.png", "wraps")
    compare(Model.next(l, "", "sequential"), "a.png", "no current: the first")
    compare(Model.next(l, "gone.png", "sequential"), "a.png")
    compare(Model.next(["only.png"], "only.png", "sequential"), "only.png")
    compare(Model.next([], "a.png", "sequential"), "")
  }

  function test_shuffleNeverRepeats() {
    const l = ["a.png", "b.png", "c.png"]
    compare(Model.next(l, "b.png", "shuffle", () => 0), "a.png")
    compare(Model.next(l, "b.png", "shuffle", () => 0.5), "c.png", "skips the current one")
    compare(Model.next(l, "b.png", "shuffle", () => 0.999), "c.png")
    compare(Model.next(l, "a.png", "shuffle", () => 0), "b.png")
    for (let i = 0; i < 50; i++)
      verify(Model.next(l, "c.png", "shuffle") !== "c.png")
  }

  function test_active() {
    verify(Model.active(false, false))
    verify(!Model.active(true, false), "on battery it waits")
    verify(Model.active(true, true), "unless the user opts in")
  }

  function test_fileName() {
    compare(Model.fileName("/usr/share/backgrounds/subarchy/01-acid.png"), "01-acid.png")
    compare(Model.fileName(""), "")
  }
}
