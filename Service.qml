import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  property bool cooldown: false

  function toggleOverview() {
    if (cooldown) return
    cooldown = true
    cooldownTimer.restart()

    if (root.shell && typeof root.shell.toggle === "function") {
      root.shell.toggle("jean.workspace-overview")
    } else {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "jean.workspace-overview"])
    }
  }

  Timer {
    id: cooldownTimer
    interval: 600
    repeat: false
    onTriggered: { root.cooldown = false }
  }

  // Hot corner surface placed on each screen in the top-left corner
  Variants {
    id: screenCorners
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: cornerWin
        required property var modelData

        screen: modelData
        color: "transparent"
        visible: true

        anchors {
          top: true
          left: true
        }

        implicitWidth: 4
        implicitHeight: 4

        WlrLayershell.namespace: "omarchy-overview-hotcorner"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        Item {
          anchors.fill: parent
          implicitWidth: 4
          implicitHeight: 4

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
              if (!root.cooldown) {
                hoverDwell.restart()
              }
            }

            onExited: {
              hoverDwell.stop()
            }
          }
        }

        Timer {
          id: hoverDwell
          interval: 100
          repeat: false
          onTriggered: {
            root.toggleOverview()
          }
        }
      }
    }
  }
}
