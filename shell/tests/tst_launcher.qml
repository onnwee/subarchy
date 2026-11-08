import QtQuick
import QtTest

import "../LauncherModel.js" as Model

TestCase {
  name: "Launcher"

  readonly property real now: 1794100000000
  readonly property real day: 86400000
  readonly property var apps: [
    { id: "kitty", name: "kitty", genericName: "Terminal emulator", keywords: ["shell", "prompt"] },
    { id: "org.kde.dolphin", name: "Dolphin", genericName: "File Manager", keywords: [] },
    { id: "zen", name: "Zen Browser", genericName: "Web Browser", keywords: ["internet"] },
    { id: "chromium", name: "Chromium", genericName: "Web Browser", keywords: [] },
    { id: "org.gnome.Nautilus", name: "Files", genericName: "", keywords: ["folder"] }
  ]

  function ids(list) {
    return list.map(a => a.id)
  }

  function test_matchStrength() {
    const zen = apps[2]
    verify(Model.match(zen, "zen") > Model.match(zen, "bro"), "a name prefix beats a word prefix")
    verify(Model.match(zen, "bro") > Model.match(zen, "row"), "a word prefix beats a substring")
    verify(Model.match(zen, "row") > Model.match(zen, "internet"), "the name beats keywords")
    compare(Model.match(zen, "vim"), 0)
    compare(Model.match(zen, ""), 1, "an empty query matches everything")
  }

  function test_everyWordMatches() {
    verify(Model.match(apps[2], "zen web") > 0)
    compare(Model.match(apps[2], "zen file"), 0)
  }

  function test_searchesGenericNameAndKeywords() {
    compare(ids(Model.rank(apps, [], {}, "terminal", now, 10)), ["kitty"])
    compare(ids(Model.rank(apps, [], {}, "folder", now, 10)), ["org.gnome.Nautilus"])
  }

  function test_favoritesFirstInTheirOrder() {
    const fav = ["chromium", "zen"]
    compare(ids(Model.rank(apps, fav, {}, "browser", now, 10)), ["chromium", "zen"])
    const hist = { zen: { count: 50, last: now } }
    compare(ids(Model.rank(apps, fav, hist, "browser", now, 10)), ["chromium", "zen"], "use does not reorder favorites")
  }

  function test_frecencyBeforeMatch() {
    const hist = { chromium: { count: 3, last: now - day } }
    compare(ids(Model.rank(apps, [], hist, "browser", now, 10)), ["chromium", "zen"])
    compare(ids(Model.rank(apps, [], {}, "browser", now, 10)), ["zen", "chromium"],
            "unused: Zen's name matches, Chromium's only its generic name")
    compare(ids(Model.rank(apps, [], {}, "web", now, 10)), ["chromium", "zen"], "equal matches: by name")
  }

  function test_homeScreenIsTheFavorites() {
    compare(ids(Model.rank(apps, ["zen", "missing", "kitty", "zen"], {}, "", now, 10)), ["zen", "kitty"],
            "uninstalled and repeated favorites are skipped")
    compare(Model.rank(apps, [], { zen: { count: 9, last: now } }, "  ", now, 10).length, 0)
  }

  function test_limit() {
    compare(Model.rank(apps, [], {}, "o", now, 2).length, 2)
  }

  function test_frecencyDecays() {
    const e = { count: 2, last: now - day }
    verify(Model.frecency(e, now) > Model.frecency({ count: 2, last: now - 20 * day }, now))
    verify(Model.frecency({ count: 5, last: now - 200 * day }, now) > 0)
    compare(Model.frecency(null, now), 0)
    compare(Model.frecency({ count: 0, last: now }, now), 0)
  }

  function test_record() {
    let h = Model.record({}, "zen", now, 10)
    h = Model.record(h, "zen", now + 1000, 10)
    compare(h.zen.count, 2)
    compare(h.zen.last, now + 1000)
    const old = { a: { count: 1, last: now - 100 * day }, b: { count: 9, last: now } }
    compare(Object.keys(Model.record(old, "c", now, 2)).sort(), ["b", "c"], "the least frecent goes first")
    compare(old.c, undefined, "the old history is not changed")
  }

  function test_favoritesConfig() {
    compare(Model.favorites('{"favorites": ["kitty", "zen.desktop", 3, ""]}'), ["kitty", "zen"])
    compare(Model.favorites('{"favorites": []}'), [])
    compare(Model.favorites(""), null)
    compare(Model.favorites("{broken"), null)
    compare(Model.favorites('{"other": 1}'), null)
  }

  function test_parseHistory() {
    compare(Model.parseHistory('{"zen": {"count": 2, "last": 5}, "bad": {"count": 0, "last": 1}, "x": 3}'),
            { zen: { count: 2, last: 5 } })
    compare(Model.parseHistory("{broken"), {})
    compare(Model.parseHistory("[1]"), {})
    compare(Model.parseHistory(""), {})
  }

  function test_move() {
    compare(Model.move(0, -1, 3), 0)
    compare(Model.move(1, 1, 3), 2)
    compare(Model.move(2, 1, 3), 2)
    compare(Model.move(0, 1, 0), -1)
  }
}
