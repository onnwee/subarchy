import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Audio"

  function test_devices() {
    const d = Model.devices([
      { id: 1, type: 17, isStream: false, isSink: true },   // Audio|Sink
      { id: 2, type: 9, isStream: false, isSink: false },   // Audio|Source
      { id: 3, type: 21, isStream: true, isSink: true },    // a playing app
      { id: 4, type: 10, isStream: false, isSink: false },  // a webcam
      { id: 5, type: 0, isStream: false, isSink: false }    // a video stream
    ])
    compare(d.sinks.map(n => n.id), [1])
    compare(d.sources.map(n => n.id), [2])
    compare(Model.devices(null), { sinks: [], sources: [] })
  }

  function test_volumeAt() {
    compare(Model.volumeAt(50, 200), 0.25)
    compare(Model.volumeAt(-5, 200), 0)
    compare(Model.volumeAt(300, 200), 1)
    compare(Model.volumeAt(10, 0), 0)
  }
}
