import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Downloads"

  function test_url() {
    compare(Model.url("https://www.youtube.com/watch?v=abc"), "https://www.youtube.com/watch?v=abc")
    compare(Model.url("look at https://x.test/v/1), great"), "https://x.test/v/1")
    compare(Model.url("youtube.com/watch?v=abc"), "https://youtube.com/watch?v=abc", "a bare host gets https")
    compare(Model.url("just words"), "")
    compare(Model.url("/etc/passwd"), "")
    compare(Model.url(""), "")
    compare(Model.url("javascript:alert(1)"), "")
  }

  function test_progress() {
    compare(Model.progress("[download]  12.3% of 10.00MiB at 1.00MiB/s ETA 00:05"), { percent: 12.3, size: "10.00MiB", speed: "1.00MiB/s", eta: "00:05" })
    compare(Model.progress("[download] 100% of   10.00MiB in 00:00:09 at 1.08MiB/s"), { percent: 100, size: "10.00MiB", speed: "1.08MiB/s", eta: "" })
    compare(Model.progress("[download]   0.0% of ~ 12.00MiB at Unknown B/s ETA Unknown"), { percent: 0, size: "12.00MiB", speed: "Unknown B/s", eta: "Unknown" })
    compare(Model.progress("[download]  55.5%"), { percent: 55.5, size: "", speed: "", eta: "" })
    compare(Model.progress("[info] Downloading 1 format(s)"), null)
    compare(Model.progress(""), null)
  }

  function test_finishedPath() {
    compare(Model.finishedPath("/home/u/Downloads/Clip [abc].mp4"), "/home/u/Downloads/Clip [abc].mp4")
    compare(Model.finishedPath("[download] /home/u/Downloads/Clip [abc].mp4 has already been downloaded"), "/home/u/Downloads/Clip [abc].mp4")
    compare(Model.finishedPath("[download] Destination: x"), "")
  }

  function test_command() {
    const c = Model.command("https://x.test/v", "/home/u/Downloads", false)
    compare(c[0], "yt-dlp")
    compare(c[c.length - 1], "https://x.test/v")
    compare(c[c.length - 2], "--", "the URL comes after -- so it cannot be an option")
    verify(c.indexOf("--no-playlist") > 0)
    verify(c.indexOf("-x") < 0)
    const a = Model.command("https://x.test/v", "/d", true)
    verify(a.indexOf("-x") > 0 && a.indexOf("-f") < 0)
  }

  function test_queue() {
    const jobs = [{ url: "a", status: "done" }, { url: "b", status: "running" }, { url: "c", status: "queued" }]
    compare(Model.nextQueued(jobs).url, "c")
    verify(Model.active(jobs))
    verify(!Model.active([{ url: "a", status: "done" }, { url: "b", status: "failed" }]))
    compare(Model.nextQueued([]), null)
    compare(Model.expandHome("~/Downloads", "/home/u"), "/home/u/Downloads")
    compare(Model.expandHome("/tmp", "/home/u"), "/tmp")
  }
}
