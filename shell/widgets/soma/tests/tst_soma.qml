import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Soma"

  readonly property string fixture: JSON.stringify({ channels: [
    { id: "groovesalad", title: "Groove Salad", description: "Ambient beats", genre: "ambient|electronic", dj: "Rusty", listeners: "1200",
      playlists: [{ url: "https://api.somafm.com/groovesalad.pls", format: "mp3", quality: "highest" },
                  { url: "https://api.somafm.com/groovesalad130.pls", format: "aac", quality: "highest" },
                  { url: "https://api.somafm.com/groovesalad64.pls", format: "aacp", quality: "high" },
                  { url: "http://evil.example/x.pls", format: "mp3", quality: "highest" }] },
    { id: "dronezone", title: "Drone Zone", description: "", genre: "ambient", dj: "", listeners: "900",
      playlists: [{ url: "https://api.somafm.com/dronezone64.pls", format: "aacp", quality: "high" }] },
    { id: "bad id", title: "Bad", playlists: [{ url: "https://api.somafm.com/bad.pls", format: "mp3", quality: "highest" }] },
    { id: "nostreams", title: "None", playlists: [{ url: "https://somafm.example.com/x.pls", format: "mp3", quality: "highest" }] }
  ] })

  function test_parse() {
    const ch = Model.parseChannels(fixture)
    compare(ch.map(c => c.id), ["dronezone", "groovesalad"], "sorted by title; bad ids and channels without a Soma stream dropped")
    compare(ch[1].listeners, 1200)
    compare(ch[1].playlists.length, 3, "a non-Soma playlist is dropped")
    let threw = false
    try { Model.parseChannels('{"x": 1}') } catch (e) { threw = true }
    verify(threw)
  }

  function test_streamUrl() {
    const ch = Model.parseChannels(fixture)
    const gs = Model.find(ch, "groovesalad")
    compare(Model.streamUrl(gs, "aac"), "https://api.somafm.com/groovesalad130.pls")
    compare(Model.streamUrl(gs, "mp3"), "https://api.somafm.com/groovesalad.pls")
    compare(Model.streamUrl(gs, "ogg"), "https://api.somafm.com/groovesalad.pls", "an unknown format falls back to mp3")
    compare(Model.streamUrl(Model.find(ch, "dronezone"), "aac"), "https://api.somafm.com/dronezone64.pls", "then to whatever there is")
    compare(Model.streamUrl(null, "aac"), "")
  }

  function test_isSomaUrl() {
    verify(Model.isSomaUrl("https://somafm.com/channels.json"))
    verify(Model.isSomaUrl("https://ice2.somafm.com/groovesalad-128-aac"))
    verify(!Model.isSomaUrl("http://somafm.com/x"))
    verify(!Model.isSomaUrl("https://somafm.com.evil.example/x"))
    verify(!Model.isSomaUrl("https://notsomafm.com/x"))
    verify(!Model.isSomaUrl("https://somafm.com/" + "a".repeat(300)))
  }

  function test_filter() {
    const ch = Model.parseChannels(fixture)
    compare(Model.filter(ch, "drone").map(c => c.id), ["dronezone"])
    compare(Model.filter(ch, "RUSTY").map(c => c.id), ["groovesalad"])
    compare(Model.filter(ch, "  ").length, 2)
    compare(Model.filter(ch, "zzz").length, 0)
  }

  function test_ipc() {
    const ev = Model.ipcEvent('{"event":"property-change","id":1,"name":"media-title","data":"Tetris - Diving Up"}')
    compare(ev.name, "media-title")
    compare(ev.data, "Tetris - Diving Up")
    compare(Model.ipcEvent('{"request_id":0,"error":"success"}'), null)
    compare(Model.ipcEvent("garbage"), null)
    compare(Model.ipcEvent('{"event":"property-change","name":"media-title"}').data, null)
  }

  function test_nowPlaying() {
    compare(Model.nowPlaying("Tetris - Diving Up"), "Tetris - Diving Up")
    compare(Model.nowPlaying("groovesalad130.pls"), "")
    compare(Model.nowPlaying("groovesalad-128-aac"), "")
    compare(Model.nowPlaying(null), "")
  }

  function test_label() {
    const gs = Model.parseChannels(fixture)[1]
    compare(Model.label(gs, "Tetris - Diving Up"), "Groove Salad · Tetris - Diving Up")
    compare(Model.label(gs, ""), "Groove Salad")
    compare(Model.label(null, "x"), "")
    verify(Model.label(gs, "a".repeat(80)).length <= 44)
  }

  function test_mpvCommand() {
    const c = Model.mpvCommand("https://api.somafm.com/groovesalad130.pls", "/run/user/1000/subcult-soma.sock")
    compare(c[0], "mpv")
    compare(c[c.length - 1], "https://api.somafm.com/groovesalad130.pls")
    verify(c.indexOf("--input-ipc-server=/run/user/1000/subcult-soma.sock") > 0)
    verify(c.indexOf("--") === c.length - 2)
  }
}
