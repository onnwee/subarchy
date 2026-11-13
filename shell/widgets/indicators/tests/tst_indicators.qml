import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Indicators"

  // PwNodeType flags as Quickshell 0.3.2 reports them (spike #42): audio
  // streams and devices carry flags; video streams carry none.
  readonly property var screencast: ({ type: 0, name: "obs", mediaClass: "Stream/Input/Video" })
  readonly property var producer: ({ type: 0, name: "xdph-screencast", mediaClass: "Stream/Output/Video" })
  readonly property var webcam: ({ type: 10, name: "v4l2_input.pci-0000_00_14.0-usb-0_6_1.0", mediaClass: "Video/Source" })
  readonly property var player: ({ type: 21, name: "pw-play", mediaClass: "Stream/Output/Audio" })
  readonly property var mic: ({ type: 13, name: "pw-record", mediaClass: "Stream/Input/Audio" })
  readonly property var sink: ({ type: 17, name: "alsa_output", mediaClass: "Audio/Sink" })

  function test_candidate() {
    verify(Model.candidate(screencast), "an untyped node may be a video stream")
    verify(Model.candidate(producer))
    verify(!Model.candidate(webcam), "a device carries flags")
    verify(!Model.candidate(player), "an audio stream carries flags")
    verify(!Model.candidate(mic))
    verify(!Model.candidate(sink))
    verify(!Model.candidate({ type: 0, name: "Dummy-Driver" }))
    verify(!Model.candidate({ type: 0, name: "Freewheel-Driver" }))
    verify(!Model.candidate({ type: 0, name: "Midi-Bridge" }))
    verify(!Model.candidate({ type: 0, name: "bluez_midi.server" }))
    verify(!Model.candidate(null))
  }

  function test_captures() {
    compare(Model.captures([]), [])
    compare(Model.captures([{ id: 81, mediaClass: "Stream/Input/Video" }]), [81], "a client capturing video")
    compare(Model.captures([{ id: 70, mediaClass: "Stream/Output/Video" }]), [], "the screencast source alone is not a capture")
    compare(Model.captures([{ id: 70, mediaClass: "" }]), [], "a candidate whose class is not known yet")
    compare(Model.captures([{ id: 70, mediaClass: "Stream/Output/Video" }, { id: 81, mediaClass: "Stream/Input/Video" }]), [81])
  }

  // Links as pw-dump showed them on sputnik (2026-11-07): the device is the
  // link's source, the client stream its target.
  readonly property var micLink: ({ sourceType: 9, targetId: 81 })       // Audio/Source -> Stream/Input/Audio
  readonly property var duplexLink: ({ sourceType: 25, targetId: 81 })   // an audio duplex device read by a client
  readonly property var monitorLink: ({ sourceType: 17, targetId: 81 })  // Audio/Sink monitor -> desktop audio capture
  readonly property var cameraLink: ({ sourceType: 10, targetId: 90 })   // Video/Source -> Stream/Input/Video
  readonly property var screenLink: ({ sourceType: 0, targetId: 91 })    // Stream/Output/Video producer -> capture
  readonly property var playbackLink: ({ sourceType: 21, targetId: 64 }) // Stream/Output/Audio -> Audio/Sink

  function test_marks() {
    compare(Model.marks([], []), { microphone: false, camera: false, screen: false })
    compare(Model.marks([micLink], []), { microphone: true, camera: false, screen: false })
    compare(Model.marks([duplexLink], []), { microphone: true, camera: false, screen: false })
    compare(Model.marks([monitorLink], []), { microphone: false, camera: false, screen: false }, "desktop audio is not the microphone")
    compare(Model.marks([playbackLink], []), { microphone: false, camera: false, screen: false })
    compare(Model.marks([cameraLink], [90]), { microphone: false, camera: true, screen: false }, "a camera client is not a screen capture")
    compare(Model.marks([cameraLink], []), { microphone: false, camera: true, screen: false }, "the camera mark needs no tracked node")
    compare(Model.marks([screenLink], [91]), { microphone: false, camera: false, screen: true })
    compare(Model.marks([screenLink], []), { microphone: false, camera: false, screen: false }, "a link into an unknown node is nothing yet")
    compare(Model.marks([], [91]), { microphone: false, camera: false, screen: false }, "a capture client without a link holds nothing")
    compare(Model.marks([micLink, cameraLink, screenLink, null], [90, 91]), { microphone: true, camera: true, screen: true })
  }

  // Hyprland's screencast events: one start and one stop per session.
  function test_screencasts() {
    compare(Model.screencasts(0, "1,0"), 1, "a monitor capture started")
    compare(Model.screencasts(1, "1,1"), 2, "a window capture beside it")
    compare(Model.screencasts(2, "0,1"), 1)
    compare(Model.screencasts(1, "0,0"), 0)
    compare(Model.screencasts(0, "0,0"), 0, "a stop for a session started before the shell")
    compare(Model.screencasts(1, ""), 1, "unknown data changes nothing")
    compare(Model.screencasts(undefined, "1,0"), 1)
  }
}
