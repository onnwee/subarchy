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

  // --- Commands, calculator and web search

  readonly property string commandsJson: JSON.stringify({ ok: true, commands: [
    { route: "subcult font set", group: "font", summary: "Use a font", args: "<family>", dangerous: false },
    { route: "subcult font", group: "font", summary: "Fonts", args: "", dangerous: false },
    { route: "subcult app remove", group: "app", summary: "Remove apps", args: "<id>...", dangerous: true },
    { route: "subcult lock", group: "lock", summary: "Lock the session", args: "", silent: true },
    { route: "subcult secret", group: "secret", summary: "", hidden: true },
    { route: "other thing", group: "x" }
  ] })

  readonly property string systemLinks: JSON.stringify({ default: "ddg", quicklinks: {
    ddg: { name: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}" },
    yt: { name: "YouTube", url: "https://www.youtube.com/results?search_query={query}" }
  } })

  function test_parseQuery() {
    compare(Model.parseQuery("=2+2"), { mode: "calc", text: "2+2" })
    compare(Model.parseQuery("@ yt cats "), { mode: "web", text: "yt cats" })
    compare(Model.parseQuery(" firefox "), { mode: "root", text: "firefox" })
  }

  function test_looksLikeMath() {
    verify(Model.looksLikeMath("2+2"))
    verify(Model.looksLikeMath("sqrt(16)"))
    verify(Model.looksLikeMath("5 km to mi"))
    verify(!Model.looksLikeMath("firefox"))
    verify(!Model.looksLikeMath("hello world"), "words alone are not math, though qalc reads them as units")
    verify(!Model.looksLikeMath("vlc 3"))
  }

  function test_calcAnswer() {
    compare(Model.calcAnswer("8\n", "2+2*3"), "8")
    compare(Model.calcAnswer("1 / 0\n", "1/0"), "", "unevaluated")
    compare(Model.calcAnswer("error: Unmatched parenthesis.\n2\n", "(2+"), "")
    compare(Model.calcAnswer("", "2+"), "")
  }

  function test_commands() {
    const c = Model.commands(commandsJson)
    compare(c.map(x => x.id), ["subcult font set", "subcult font", "subcult app remove", "subcult lock"], "hidden and foreign routes left out")
    compare(c[0].name, "font set")
    compare(c[2].dangerous, true)
    compare(c[0].kind, "command")
    compare(Model.commands("{broken"), [])
    verify(Model.match(c[0], "font") > 0, "commands rank like apps")
    compare(c.map(x => x.silent), [false, false, false, true])
  }

  function test_commandArgv() {
    const c = Model.commands(commandsJson)
    const font = Model.commandArgv(Object.assign({}, c[0], { args: ["Iosevka Term"] }))
    compare(font.slice(0, 5), ["uwsm-app", "--", "xdg-terminal-exec", "sh", "-c"])
    verify(font[5].indexOf("Press Enter to close") >= 0, "the output stays readable")
    compare(font.slice(-4), ["sh", "font", "set", "Iosevka Term"])
    compare(Model.commandArgv(c[0]).slice(-3), ["sh", "font", "set"], "the usage text is not an argument")
    compare(Model.commandArgv(c[3]), ["uwsm-app", "--", "subcult", "lock"], "a silent command opens no terminal")
  }

  function test_commandCall() {
    const c = Model.commands(commandsJson)
    const call = Model.commandCall(c, "font set Iosevka Term")
    compare(call.command.id, "subcult font set", "the longest route wins")
    compare(call.args, ["Iosevka", "Term"])
    compare(Model.commandCall(c, "subcult font").args, [])
    compare(Model.commandCall(c, "fon"), null)
    compare(Model.commandCall(c, ""), null)
  }

  function test_quicklinksLayered() {
    const user = JSON.stringify({ default: "g", quicklinks: {
      g: { url: "https://www.google.com/search?q={query}" },
      yt: { name: "Tube", url: "https://example.org/?q={query}" },
      mail: { name: "Mail", url: "https://mail.proton.me" },
      bad: { name: "Bad", url: "javascript:alert(1)" }
    } })
    const ql = Model.quicklinks(systemLinks, user)
    compare(ql.default, "g")
    compare(ql.links.g.name, "g", "the keyword names a link without one")
    compare(ql.links.yt.name, "Tube", "the user's link replaces the system's")
    compare(ql.links.bad, undefined, "only http and https links")
    compare(Model.quicklinks(systemLinks, "{broken").default, "ddg")
    compare(Model.quicklinks(systemLinks, JSON.stringify({ default: "mail" })).default, "ddg",
            "a default must be a search link")
  }

  function test_webTarget() {
    const ql = Model.quicklinks(systemLinks, JSON.stringify({ quicklinks: { mail: { name: "Mail", url: "https://mail.proton.me" } } }))
    compare(Model.webTarget(ql, "yt cat videos").url, "https://www.youtube.com/results?search_query=cat%20videos")
    compare(Model.webTarget(ql, "a&b=c").url, "https://duckduckgo.com/?q=a%26b%3Dc", "the default engine, encoded")
    compare(Model.webTarget(ql, "yt").url, "https://duckduckgo.com/?q=yt", "a search keyword alone is a query")
    compare(Model.webTarget(ql, "mail").url, "https://mail.proton.me")
    compare(Model.webTarget(ql, "mail me").url, "https://duckduckgo.com/?q=mail%20me")
    compare(Model.webTarget(ql, "  "), null)
    compare(Model.webTarget(Model.quicklinks("", ""), "x"), null, "no engine, no target")
  }

  // --- Script commands, aliases and snippets

  readonly property string raycastScript: [
    "#!/bin/bash",
    "# Required parameters:",
    "# @raycast.schemaVersion 1",
    "# @raycast.title Search Arch packages",
    "# @raycast.mode fullOutput",
    "# Optional parameters:",
    "# @raycast.packageName Arch",
    '# @raycast.argument1 { "type": "text", "placeholder": "Package", "percentEncoded": true }',
    '# @raycast.argument2 { "type": "text", "placeholder": "Repo", "optional": true }',
    "# @raycast.needsConfirmation true",
    "# @raycast.currentDirectoryPath ~/src",
    "echo hi"
  ].join("\n")

  function test_scriptHeaders() {
    const list = Model.scripts("\x1e/home/u/.config/subcult/commands/pkg.sh\n" + raycastScript
      + "\x1e/home/u/.config/subcult/commands/plain.sh\n#!/bin/sh\necho no header\n"
      + "\x1e/home/u/.config/subcult/commands/inline.py\n#!/usr/bin/env python3\n# @subcult.title Clock\n# @raycast.mode inline\n")
    compare(list.length, 2, "a script without a title is not a command")
    const s = list[0]
    compare(s.id, "script:pkg.sh")
    compare(s.name, "Search Arch packages")
    compare(s.mode, "fullOutput")
    compare(s.genericName, "Arch")
    compare(s.dangerous, true, "needsConfirmation asks first")
    compare(s.dir, "~/src")
    compare(s.params, [{ placeholder: "Package", optional: false, percentEncoded: true }, { placeholder: "Repo", optional: true, percentEncoded: false }])
    compare(Model.requiredArgs(s), 1)
    compare(list[1].mode, "compact", "inline runs as compact")
    compare(list[1].dir, "/home/u/.config/subcult/commands", "the script's folder by default")
  }

  function test_splitArgs() {
    compare(Model.splitArgs("linux zen kernel", 2), ["linux", "zen kernel"], "the last argument takes the rest")
    compare(Model.splitArgs("one", 3), ["one"])
    compare(Model.splitArgs("  ", 2), [])
    compare(Model.splitArgs("a b", 0), [])
  }

  function test_scriptArgv() {
    const s = Model.scripts("\x1e/c/pkg.sh\n" + raycastScript)[0]
    const full = Model.scriptArgv(s, ["a b&c"], "/home/u")
    compare(full.slice(0, 4), ["uwsm-app", "--", "xdg-terminal-exec", "sh"])
    compare(full.slice(-3), ["/home/u/src", "/c/pkg.sh", "a%20b%26c"], "the home folder and percent encoding")
    const silent = Model.scriptArgv(Object.assign({}, s, { mode: "silent", dir: "/w" }), ["x"], "/home/u")
    compare(silent[0], "sh")
    compare(silent.slice(-3), ["/w", "/c/pkg.sh", "x"])
    const compact = Model.scriptArgv(Object.assign({}, s, { mode: "compact", dir: "/w" }), [], "/home/u")
    compare(compact.slice(-3), ["/w", "Search Arch packages", "/c/pkg.sh"])
    verify(compact[2].indexOf("notify-send") >= 0)
  }

  function test_aliases() {
    const names = Model.aliases('{"aliases": {"up": "subcult update", "bad name": "x", "e": "", "pkg": "script:pkg.sh"}}')
    compare(names, { up: "subcult update", pkg: "script:pkg.sh" })
    compare(Model.aliases("{broken"), {})
    const items = [{ id: "subcult update", name: "update" }, { id: "script:pkg.sh", name: "Search" }]
    const r = Model.resolveAlias(names, items, "pkg linux zen")
    compare(r.item.id, "script:pkg.sh")
    compare(r.rest, "linux zen")
    compare(Model.resolveAlias(names, items, "upx"), null)
    compare(Model.resolveAlias({ gone: "nothing" }, items, "gone"), null, "an alias to a missing item")
    compare(Model.resolveAlias(names, items, "toString"), null, "only the user's own names")
  }

  function test_snippets() {
    const list = Model.snippets('{"snippets": [{"name": "Date", "keyword": "dt", "text": "{date}"}]}',
      '{"snippets": [{"name": "Sign-off", "text": "Best,\\n  Pat"}, {"name": "", "text": "x"}, {"name": "No text"}]}')
    compare(list.map(x => x.id), ["snippet:Date", "snippet:Sign-off"])
    compare(list[0].keywords, ["dt"])
    compare(list[1].genericName, "Best, Pat")
    compare(Model.snippets("{broken", "").length, 0)
  }

  function test_expand() {
    const d = new Date(2026, 10, 7, 9, 5)
    compare(Model.expand("{date} {time} [{clipboard}] {other}", d, "copied"), "2026-11-07 09:05 [copied] {other}")
    compare(Model.expand("{clipboard}", d, null), "")
  }

  function test_parseQueryPrefixes() {
    compare(Model.parseQuery(". report"), { mode: "files", text: "report" })
    compare(Model.parseQuery("."), { mode: "files", text: "" })
    compare(Model.parseQuery(":heart"), { mode: "symbols", text: "heart" })
    compare(Model.parseQuery(".5 * 2"), { mode: "files", text: "5 * 2" }, "a leading dot is the files prefix")
  }

  function test_files() {
    const rows = Model.files("f /home/pat/Documents/report.pdf\nd /home/pat/Music\nf /etc/hosts\nodd line\n\n", "/home/pat")
    compare(rows.map(r => r.name), ["report.pdf", "Music", "hosts"])
    compare(rows.map(r => r.genericName), ["~/Documents", "~", "/etc"])
    compare(rows.map(r => r.icon), ["application-pdf", "folder", "text-x-generic"])
    compare(rows[0].kind, "file")
    compare(rows[0].id, "/home/pat/Documents/report.pdf")
    compare(rows[1].isDir, true)
    compare(Model.files("", "/home/pat"), [])
    verify(Model.isImage("/x/photo.JPG"))
    verify(!Model.isImage("/x/photo.jpg.txt"))
    compare(Model.fileIcon("/x/a.webp"), "image-x-generic")
    compare(Model.fileIcon("/x/a.flac"), "audio-x-generic")
    compare(Model.fileIcon("/x/a.mkv"), "video-x-generic")
  }

  function test_fdArgv() {
    const a = Model.fdArgv("report", "/home/pat")
    compare(a.slice(0, 2), ["sh", "-c"])
    compare(a.slice(-2), ["report", "/home/pat"], "the text is an argument, never part of the script")
    verify(a[2].indexOf("--fixed-strings") >= 0, "the text is not a regex")
    verify(a[2].indexOf("--max-results 60") >= 0)
    verify(Model.previewArgv("/x/a b").slice(-1)[0] === "/x/a b")
  }

  function test_emoji() {
    const data = "# emoji-test.txt\n# group: Smileys & Emotion\n# subgroup: face-smiling\n"
      + "1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face\n"
      + "263A                                                   ; unqualified         # ☺ E0.6 smiling face\n"
      + "# group: Symbols\n"
      + "2764 FE0F                                              ; fully-qualified     # ❤️ E0.6 red heart\n"
      + "0023 FE0F 20E3                                         ; fully-qualified     # #️⃣ E0.6 keycap: #\n"
    const list = Model.emoji(data)
    compare(list.map(e => e.name), ["grinning face", "red heart", "keycap: #"], "fully-qualified only")
    compare(list.map(e => e.genericName), ["Smileys & Emotion", "Symbols", "Symbols"])
    compare(list[1].char, "\u2764\uFE0F")
    compare(list[1].id, "symbol:\u2764\uFE0F")
    compare(list[0].kind, "symbol")
    compare(Model.emoji("").length, 0)
    // The launcher's ranking finds them by name words.
    compare(Model.rank(list, [], {}, "heart", 0, 10).map(e => e.name), ["red heart"])
  }

  function test_ask() {
    compare(Model.agent('{"id": "claude-code", "name": "Claude Code", "argv": ["claude", "-p"]}'), { id: "claude-code", name: "Claude Code" })
    compare(Model.agent(""), null)
    compare(Model.agent('{"id": "", "name": "x"}'), null)
    compare(Model.agent("subcult app: no default agent"), null, "an error message is no agent")
    const row = Model.askRow({ id: "claude-code", name: "Claude Code" }, "what is zram")
    compare(row.kind, "ask")
    compare(row.id, "ask:claude-code")
    compare(row.name, "Ask Claude Code: \u201cwhat is zram\u201d")
    verify(row.genericName.indexOf("leaves this machine") >= 0, "the row says the text leaves the machine")
    compare(row.text, "what is zram")
    compare(Model.askRow(null, "x"), null, "no agent, no row")
    compare(Model.askRow({ id: "a", name: "A" }, ""), null)
  }

  function test_clipboard() {
    const list = Model.clipboard('[{"id": "aaaa", "kind": "text", "mime": "text/plain", "size": 11, "time": "2026-11-07T22:00:00Z", "preview": "hello world"},'
      + ' {"id": "bbbb", "kind": "image", "mime": "image/png", "size": 5, "time": "bad", "preview": "Image, 5 bytes", "file": "/s/bbbb.png"}, {"kind": "text"}]')
    compare(list.map(c => c.id), ["clip:aaaa", "clip:bbbb"])
    compare(list[0].clipId, "aaaa")
    compare(list[0].name, "hello world")
    compare(list[0].icon, "edit-paste")
    verify(list[0].genericName.indexOf("Text, ") === 0)
    compare(list[1].isImage, true)
    compare(list[1].file, "/s/bbbb.png")
    compare(list[1].genericName, "Image", "an unreadable time is left out")
    compare(Model.clipboard("not json"), [])
    compare(Model.clipboard('{"x": 1}'), [])
    compare(Model.clipClear.kind, "clipclear")
    compare(Model.parseQuery("$old"), { mode: "clipboard", text: "old" })
    compare(Model.match(list[0], "hello"), 4, "entries filter by their text")
  }

  function test_symbols() {
    const list = Model.symbols('{"symbols": [{"char": "—", "name": "em dash", "group": "Punctuation"}, {"char": "→", "name": "right arrow"}, {"char": "", "name": "x"}, {"name": "no char"}]}')
    compare(list.map(x => x.char), ["—", "→"])
    compare(list.map(x => x.genericName), ["Punctuation", "Symbols"])
    compare(Model.symbols("{broken"), [])
    compare(Model.symbols('{"symbols": 3}'), [])
  }

  // Object.prototype has members named like these words.
  function test_webTargetWithAWordObjectsAlsoHave() {
    const ql = Model.quicklinks(systemLinks, "")
    for (const word of ["constructor", "toString", "valueOf", "hasOwnProperty", "__proto__"]) {
      compare(Model.webTarget(ql, word + " theory").url, "https://duckduckgo.com/?q=" + word + "%20theory", word)
      compare(Model.webTarget(ql, word).url, "https://duckduckgo.com/?q=" + word, word + " alone")
    }
  }

  // Holding Enter on a dangerous row must stop at the question: the second
  // event of a held key is a repeat, and the warning has not been read.
  function test_aHeldEnterDoesNotConfirmADangerousCommand() {
    verify(Model.confirms(false), "a new press confirms")
    verify(!Model.confirms(true), "a repeat of the press that asked does not")
  }
}
