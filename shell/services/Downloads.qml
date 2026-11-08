pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/downloads/Model.js" as Model

// The download queue behind the downloads widget: one yt-dlp at a time,
// started only when a job is queued; nothing runs otherwise. Progress comes
// from yt-dlp's own lines; a finished download is announced through
// notify-send.
Singleton {
  id: root

  property var jobs: []
  property int nextId: 1

  function add(url, settings) {
    const s = settings || {}
    const job = {
      id: root.nextId++, url: url, status: "queued", percent: 0, speed: "", eta: "", title: "", file: "", error: "",
      directory: Model.expandHome(s.directory || "~/Downloads", Quickshell.env("HOME")),
      audioOnly: s.audioOnly === true
    }
    root.jobs = root.jobs.concat([job])
    root.pump()
  }

  function remove(id) {
    root.jobs = root.jobs.filter(j => j.id !== id || j.status === "running")
  }

  function update(id, fields) {
    root.jobs = root.jobs.map(j => j.id === id ? Object.assign({}, j, fields) : j)
  }

  // Starts the next queued job when none runs.
  function pump() {
    if (runner.running)
      return
    const job = Model.nextQueued(root.jobs)
    if (!job)
      return
    runner.jobId = job.id
    runner.command = Model.command(job.url, job.directory, job.audioOnly)
    root.update(job.id, { status: "running" })
    runner.running = true
  }

  Process {
    id: runner
    property int jobId: 0
    stdout: SplitParser {
      onRead: (line) => {
        const p = Model.progress(line)
        if (p) {
          root.update(runner.jobId, { percent: p.percent, speed: p.speed, eta: p.eta })
          return
        }
        const f = Model.finishedPath(line)
        if (f !== "")
          root.update(runner.jobId, { file: f, title: Model.fileName(f) })
      }
    }
    stderr: SplitParser {
      onRead: (line) => {
        if (/^ERROR/.test(line))
          root.update(runner.jobId, { error: line.replace(/^ERROR:\s*/, "").slice(0, 120) })
      }
    }
    onExited: (code) => {
      const job = root.jobs.find(j => j.id === runner.jobId)
      const ok = code === 0
      root.update(runner.jobId, { status: ok ? "done" : "failed", percent: ok ? 100 : 0 })
      if (job)
        Quickshell.execDetached(["notify-send", "-a", "Downloads", "-i", "folder-download", "--",
          ok ? "Download finished" : "Download failed", ok ? Model.fileName(job.file || job.url) : (job.error || job.url)])
      root.pump()
    }
  }

  IpcHandler {
    target: "subcult.downloads"
    function add(url: string): void { root.add(Model.url(url), {}) }
    function state(): string { return JSON.stringify(root.jobs.map(j => ({ id: j.id, status: j.status, percent: j.percent, file: j.file }))) }
  }
}
