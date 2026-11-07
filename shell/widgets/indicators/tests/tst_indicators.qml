import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Indicators"

  function test_recording() {
    verify(!Model.recording([]))
    verify(!Model.recording([{ isStream: true, mediaClass: "Stream/Output/Audio" }]))
    verify(Model.recording([{ isStream: true, mediaClass: "Stream/Input/Video" }]), "a client capturing video")
    verify(!Model.recording([{ isStream: false, mediaClass: "Video/Source" }]), "a camera device alone is not a capture")
  }
}
