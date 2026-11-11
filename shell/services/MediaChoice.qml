pragma Singleton
import QtQuick
import Quickshell

// The media player the user chose in the media panel (its D-Bus name), so
// the bar widget on every output and the panel agree. Empty until a choice
// is made; a choice whose player has closed is ignored by Model.pick.
Singleton {
  property string chosenId: ""
}
