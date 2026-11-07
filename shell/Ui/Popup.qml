import QtQuick
import qs.Commons

// The frame of a panel: mantle background, 1 px border, padding. Panels
// put their content inside.
Rectangle {
  default property alias content: inner.data

  implicitWidth: inner.childrenRect.width + 2 * Style.spacing
  implicitHeight: inner.childrenRect.height + 2 * Style.spacing
  color: Theme.mantle
  border.color: Theme.border
  border.width: 1

  Item {
    id: inner
    x: Style.spacing
    y: Style.spacing
    width: childrenRect.width
    height: childrenRect.height
  }
}
