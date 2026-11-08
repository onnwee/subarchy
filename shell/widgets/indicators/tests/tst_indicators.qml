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

  function test_recording() {
    verify(!Model.recording([]))
    verify(Model.recording([screencast]), "a client capturing video")
    verify(!Model.recording([producer]), "the screencast source alone is not a capture")
    verify(!Model.recording([{ mediaClass: "" }]), "a candidate whose class is not known yet")
    verify(Model.recording([producer, screencast]))
  }
}
