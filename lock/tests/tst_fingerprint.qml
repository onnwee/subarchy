import QtQuick
import QtTest
import "../FingerprintModel.js" as Fingerprint

TestCase {
  name: "Fingerprint"

  // fprintd-list as fprintd 1.94 prints it. Only an enrolled finger turns
  // fingerprint unlock on; no reader, no finger and no fprintd keep it off.
  function test_probe() {
    compare(Fingerprint.classifyProbe("Using device /net/reactivated/Fprint/Device/0\nFingerprints for user pat on Synaptics Sensors (press):\n - #0: right-index-finger\n"), "yes")
    compare(Fingerprint.classifyProbe("No devices available\n"), "no", "no reader")
    compare(Fingerprint.classifyProbe("Using device /net/reactivated/Fprint/Device/0\nUser pat has no fingers enrolled for Synaptics Sensors.\n"), "no", "no finger")
    compare(Fingerprint.classifyProbe("no\n"), "no", "no fprintd or no PAM service")
    compare(Fingerprint.classifyProbe("Failed to connect to session bus: Could not connect\n"), "unknown")
    compare(Fingerprint.classifyProbe(""), "unknown")
    compare(Fingerprint.classifyProbe(undefined), "unknown")
    compare(Fingerprint.classifyProbe("Fingerprints for user pat on A (press):\n - #0: left-thumb\nUser pat has no fingers enrolled for B.\n"), "yes", "one of two readers")
  }

  function test_probeRetries() {
    compare(Fingerprint.probeRetryMs(1), 2000)
    compare(Fingerprint.probeRetryMs(2), 4000)
    compare(Fingerprint.probeRetryMs(10), 60000)
  }

  // An attempt that waited for a finger restarts at once; one that fails
  // straight away backs off, and three in a row say the reader is out.
  function test_settle() {
    let r = Fingerprint.settle(0, 30000)
    compare(r.streak, 0)
    compare(r.delayMs, 250)
    r = Fingerprint.settle(0, 50)
    compare(r.streak, 1)
    compare(r.delayMs, 1000)
    r = Fingerprint.settle(r.streak, 50)
    r = Fingerprint.settle(r.streak, 50)
    compare(r.streak, 3)
    compare(r.delayMs, 4000)
    verify(Fingerprint.isUnavailable(r.streak))
    verify(!Fingerprint.isUnavailable(2))
    compare(Fingerprint.settle(20, 0).delayMs, 40000, "capped")
    compare(Fingerprint.settle(5, 9000).streak, 0, "a slow attempt reached the reader")
  }

  function test_messages() {
    compare(Fingerprint.message("ready", "Failed to match fingerprint", true), "nomatch")
    compare(Fingerprint.message("ready", "Verification timed out", true), "ready", "a timeout is not a wrong finger")
    compare(Fingerprint.message("unavailable", "Place your finger on Synaptics Sensors", false), "ready", "the reader answers again")
    compare(Fingerprint.message("nomatch", "Place your finger on the reader again", false), "nomatch")
    compare(Fingerprint.message("off", "Failed to match fingerprint", true), "off", "nothing shows without a reader")
  }

  function test_text() {
    compare(Fingerprint.hint("off"), "")
    verify(Fingerprint.hint("ready").indexOf("fingerprint") > 0)
    verify(Fingerprint.hint("nomatch") !== "")
    verify(Fingerprint.hint("unavailable").indexOf("password") > 0)
    compare(Fingerprint.idleText("off"), "Press a key to unlock")
    verify(Fingerprint.idleText("ready").indexOf("reader") > 0)
  }
}
