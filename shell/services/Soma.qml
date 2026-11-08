pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/soma/Model.js" as Model

// SomaFM playback, shared by the bar widget and its panel. The channel list
// is fetched when asked (the panel opening); a channel plays through mpv,
// whose JSON IPC socket reports the stream's title as it changes, so
// now-playing is an event, not a poll. Nothing runs while stopped.
Singleton {
  id: root

  property var channels: []
  property string channelsError: ""
  property double channelsAt: 0
  property string channelId: ""
  property string format: "aac"
  readonly property var channel: Model.find(channels, channelId)
  readonly property bool playing: mpv.running
  property string song: ""
  property string playError: ""
  property string pendingUrl: ""
  property bool stopping: false
  property int attempts: 0

  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/subcult-soma.sock"

  function loadChannels() {
    if (!fetch.running && Date.now() - root.channelsAt > 600000)
      fetch.running = true
  }

  function play(id) {
    const c = Model.find(root.channels, id)
    const url = Model.streamUrl(c, root.format)
    if (url === "")
      return false
    root.channelId = id
    root.song = ""
    root.playError = ""
    if (mpv.running) {
      // The old mpv must be gone before the new one starts, or its exit
      // would tear down the new one's socket: start from onExited.
      root.pendingUrl = url
      connectTimer.stop()
      ipc.connected = false
      mpv.running = false
      return true
    }
    root.start(url)
    return true
  }

  function start(url) {
    mpv.command = Model.mpvCommand(url, root.socketPath)
    mpv.running = true
    root.attempts = 0
    connectTimer.start()
  }

  function stop() {
    root.pendingUrl = ""
    connectTimer.stop()
    ipc.connected = false
    if (mpv.running) {
      root.stopping = true
      mpv.running = false
    }
    root.song = ""
  }

  function toggle() {
    if (root.playing)
      root.stop()
    else if (root.channelId !== "")
      root.play(root.channelId)
  }

  Process {
    id: fetch
    command: ["curl", "-sf", "--max-time", "15", "https://somafm.com/channels.json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.channels = Model.parseChannels(text)
          root.channelsError = ""
          root.channelsAt = Date.now()
        } catch (e) {
          root.channelsError = "SomaFM's channel list did not load"
        }
      }
    }
    onExited: (code) => {
      if (code !== 0)
        root.channelsError = "SomaFM's channel list did not load"
    }
  }

  Process {
    id: mpv
    onExited: (code) => {
      connectTimer.stop()
      ipc.connected = false
      root.song = ""
      const wasStopping = root.stopping
      root.stopping = false
      if (root.pendingUrl !== "") {
        const url = root.pendingUrl
        root.pendingUrl = ""
        root.start(url)
      } else if (!wasStopping && code !== 0) {
        root.playError = (root.channel ? root.channel.title : "The stream") + " did not play (mpv exit " + code + ")"
      }
    }
  }

  // mpv creates its socket a moment after it starts: try to connect a few
  // times, 100 ms apart, then give up on the title (playback is unaffected).
  Timer {
    id: connectTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (!mpv.running)
        return
      root.attempts++
      ipc.connected = true
    }
  }

  Socket {
    id: ipc
    path: root.socketPath
    parser: SplitParser {
      onRead: (line) => {
        const ev = Model.ipcEvent(line)
        if (ev && ev.name === "media-title")
          root.song = Model.nowPlaying(ev.data)
      }
    }
    onConnectedChanged: {
      if (connected) {
        ipc.write(Model.observe())
        ipc.flush()
      }
    }
    onError: {
      if (mpv.running && root.attempts < 30)
        connectTimer.start()
    }
  }

  IpcHandler {
    target: "subcult.soma"
    function play(id: string): bool { return root.play(id) }
    function stop(): void { root.stop() }
    function toggle(): void { root.toggle() }
    function state(): string {
      return JSON.stringify({ playing: root.playing, channel: root.channelId, song: root.song, channels: root.channels.length, error: root.playError })
    }
  }
}
