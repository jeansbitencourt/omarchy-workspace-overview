import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

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

  // Background capture process to keep inactive workspaces authentic as user works
  Process {
    id: bgCaptureProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/jean.workspace-overview/capture-previews.sh"]
  }

  Timer {
    id: bgCaptureDebounce
    interval: 350
    repeat: false
    onTriggered: {
      var isOverviewOpen = false
      if (root.shell && typeof root.shell.isPluginOpen === "function") {
        isOverviewOpen = root.shell.isPluginOpen("jean.workspace-overview")
      }
      if (!isOverviewOpen && !bgCaptureProc.running) {
        bgCaptureProc.running = true
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "workspacev2" || name === "workspace" || name === "focusedmon" ||
          name === "openwindow" || name === "closewindow") {
        bgCaptureDebounce.restart()
      }
    }
  }

  Component.onCompleted: {
    bgCaptureDebounce.restart()
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
