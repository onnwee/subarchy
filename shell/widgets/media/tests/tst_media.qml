import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Media"

  readonly property var players: [
    { id: "a", playing: false, identity: "Zen" },
    { id: "b", playing: true, identity: "mpv" },
    { id: "c", playing: true, identity: "Spotify" }
  ]

  function test_pick() {
    compare(Model.pick(players, "").id, "b", "the first playing one")
    compare(Model.pick(players, "c").id, "c", "the user's choice")
    compare(Model.pick(players, "gone").id, "b", "a choice that went away")
    compare(Model.pick([players[0]], "").id, "a", "the only one, even paused")
    compare(Model.pick([], ""), null)
  }

  function test_artSource() {
    compare(Model.artSource("file:///home/u/.cache/art.jpg"), "file:///home/u/.cache/art.jpg")
    compare(Model.artSource("https://i.scdn.co/image/abc"), "", "remote artwork is not fetched")
    compare(Model.artSource("http://x.test/a.png"), "")
    compare(Model.artSource(""), "")
    compare(Model.artSource(null), "")
  }

  function test_label() {
    compare(Model.label("Song", "Band", "mpv", 40), "Band – Song")
    compare(Model.label("Song", "", "mpv", 40), "Song")
    compare(Model.label("", "", "mpv", 40), "mpv")
    compare(Model.label("A very long title that goes on", "Band", "x", 12), "Band – A ve…")
    compare(Model.label("  spaced   out ", "", "x", 40), "spaced out")
  }
}
