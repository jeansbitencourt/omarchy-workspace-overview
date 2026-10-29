import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property int activeWsId: 1
  property int viewWsId: 1
  property var workspaceList: []
  property var currentWindows: []
  property int previewGen: 1

  // Glassy / translucent styling tokens
  readonly property color scrimColor: Qt.rgba(0.04, 0.06, 0.10, 0.45)
  readonly property color glassCardBg: Qt.rgba(0.10, 0.14, 0.20, 0.60)
  readonly property color glassCardHoverBg: Qt.rgba(0.18, 0.24, 0.32, 0.70)
  readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.18)
  readonly property color glassBorderHighlight: Commons.Color.accent

  readonly property color fg: Commons.Color.foreground
  readonly property color accentCol: Commons.Color.accent
  readonly property color mutedCol: Commons.Color.muted
  readonly property string monoFont: Style.fontFamily
  readonly property string bodyFont: Style.font.menuFamily

  // Fast background preview capture
  Process {
    id: previewProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/jean.workspace-overview/capture-previews.sh"]
    onExited: {
      openSafetyTimer.stop()
      root.opened = true
      root.rebuild()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: openSafetyTimer
    interval: 160
    repeat: false
    onTriggered: {
      root.opened = true
      root.rebuild()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  // Translations
  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function open(payloadJson) {
    root.filterText = ""
    root.selectedIndex = 0

    if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace) {
      root.activeWsId = Hyprland.focusedMonitor.activeWorkspace.id
      root.viewWsId = root.activeWsId
    }

    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()

    // Capture clean screen before overlay is mapped
    if (!previewProc.running) {
      openSafetyTimer.restart()
      previewProc.running = true
    } else {
      root.opened = true
      root.rebuild()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "jean.workspace-overview")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("")
  }

  function rebuild() {
    var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []

    var actWs = (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace)
      ? Hyprland.focusedMonitor.activeWorkspace.id : root.activeWsId
    root.activeWsId = actWs

    var filterLower = root.filterText.toLowerCase().trim()

    // Map windows to workspaces
    var wsWindowsMap = {}
    var allFilteredWins = []

    for (var j = 0; j < toplevels.length; j++) {
      var top = toplevels[j]
      var topWs = top.workspace ? top.workspace.id : -1
      if (topWs <= 0) continue

      var raw = top.lastIpcObject || {}
      var title = String(raw.title || top.title || (top.wayland ? top.wayland.title : "") || "")
      var appClass = String(raw.class || (top.wayland ? top.wayland.appId : "") || "")
      var addrRaw = String(raw.address || top.address || "")
      var cleanAddr = addrRaw.replace(/^0x/, "")
      var fullAddr = "0x" + cleanAddr

      if (filterLower !== "") {
        if (title.toLowerCase().indexOf(filterLower) === -1 &&
            appClass.toLowerCase().indexOf(filterLower) === -1) {
          continue
        }
      }

      var winObj = {
        address: fullAddr,
        cleanAddress: cleanAddr,
        title: title,
        appClass: appClass,
        workspaceId: topWs,
        focused: !!top.activated,
        floating: !!raw.floating,
        fullscreen: !!raw.fullscreen,
        width: (raw.size && raw.size[0] && raw.size[0] > 0) ? raw.size[0] : 800,
        height: (raw.size && raw.size[1] && raw.size[1] > 0) ? raw.size[1] : 600
      }

      if (!wsWindowsMap[topWs]) wsWindowsMap[topWs] = []
      wsWindowsMap[topWs].push(winObj)
      allFilteredWins.push(winObj)
    }

    // Only workspaces that have open windows!
    var wsIds = Object.keys(wsWindowsMap).map(function(x) { return parseInt(x, 10) })
    wsIds.sort(function(a, b) { return a - b })

    var wsData = []
    for (var w = 0; w < wsIds.length; w++) {
      var id = wsIds[w]
      wsData.push({
        id: id,
        name: String(id),
        isActive: id === root.activeWsId,
        windows: wsWindowsMap[id]
      })
    }

    // Fallback if no workspaces have open windows: show active workspace as empty
    if (wsData.length === 0) {
      wsData.push({
        id: root.activeWsId,
        name: String(root.activeWsId),
        isActive: true,
        windows: []
      })
      root.viewWsId = root.activeWsId
    } else if (wsIds.indexOf(root.viewWsId) === -1) {
      root.viewWsId = wsIds[0]
    }

    root.workspaceList = wsData

    if (filterLower !== "") {
      root.currentWindows = allFilteredWins
    } else {
      root.currentWindows = wsWindowsMap[root.viewWsId] || []
    }

    if (root.selectedIndex >= root.currentWindows.length) {
      root.selectedIndex = Math.max(0, root.currentWindows.length - 1)
    }
  }

  function activateWindow(win) {
    if (!win || !win.address) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + win.address + '" })')
    root.dismiss()
  }

  function focusWorkspace(id) {
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
    root.viewWsId = id
    root.rebuild()
  }

  function closeWindow(address) {
    if (!address) return
    Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
    Qt.callLater(function() {
      Hyprland.refreshToplevels()
      root.rebuild()
    })
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.opened) {
        root.rebuild()
      }
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-workspace-overview"

    // Translucent glassy scrim with desktop blur
    Rectangle {
      anchors.fill: parent
      color: root.scrimColor

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    // Main Stage Area (Gnome Overview Canvas)
    Item {
      id: stage
      anchors.fill: parent
      anchors.topMargin: 36
      anchors.bottomMargin: 36
      anchors.leftMargin: 48
      anchors.rightMargin: 48

      opacity: panel.contentRevealed ? 1 : 0
      scale: panel.contentRevealed ? 1 : 0.98
      Behavior on opacity {
        NumberAnimation {
          duration: Style.duration(180)
          easing.type: Easing.OutCubic
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: Style.duration(180)
          easing.type: Easing.Bezier
          easing.bezierCurve: Style.easeOut
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {} // Keep inside clicks
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText.length > 0) {
              root.filterText = ""
              root.rebuild()
            } else {
              root.dismiss()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            if (event.modifiers & Qt.ShiftModifier) {
              if (root.currentWindows.length > 0) {
                root.selectedIndex = (root.selectedIndex - 1 + root.currentWindows.length) % root.currentWindows.length
              }
            } else {
              if (root.currentWindows.length > 0) {
                root.selectedIndex = (root.selectedIndex + 1) % root.currentWindows.length
              }
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            if (root.currentWindows.length > 0) {
              root.selectedIndex = (root.selectedIndex - 1 + root.currentWindows.length) % root.currentWindows.length
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (root.currentWindows.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.currentWindows.length) {
              root.activateWindow(root.currentWindows[root.selectedIndex])
            }
            event.accepted = true
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && root.filterText.length === 0) {
            var targetWs = event.key - Qt.Key_0
            root.focusWorkspace(targetWs)
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) {
              root.filterText = root.filterText.substring(0, root.filterText.length - 1)
              root.rebuild()
              event.accepted = true
            }
          } else if (event.text && event.text.length === 1 && !event.modifiers) {
            root.filterText += event.text
            root.rebuild()
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: 20

          // ============================================ TOP HEADER
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            // Gnome Search Pill
            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              implicitWidth: Math.min(460, stage.width * 0.45)
              implicitHeight: 38
              radius: 19
              color: root.glassCardBg
              border.color: root.filterText.length > 0 ? root.accentCol : root.glassBorder
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: Style.spacing.sm

                Text {
                  textFormat: Text.PlainText
                  font.family: root.monoFont
                  font.pixelSize: 14
                  color: root.filterText.length > 0 ? root.accentCol : root.mutedCol
                  text: "󰍉"
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  font.family: root.bodyFont
                  font.pixelSize: Style.font.body
                  color: root.filterText.length > 0 ? root.fg : root.mutedCol
                  text: root.filterText.length > 0 ? root.filterText : strings.t("search")
                  elide: Text.ElideRight
                }

                Text {
                  visible: root.filterText.length > 0
                  textFormat: Text.PlainText
                  font.family: root.monoFont
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                  text: "[ESC]"
                }
              }
            }

            // Workspaces Pill Strip (Only workspaces with windows!)
            Rectangle {
              id: wsBar
              Layout.alignment: Qt.AlignHCenter
              implicitHeight: 38
              implicitWidth: wsRow.width + 16
              visible: root.workspaceList.length > 0
              radius: 19
              color: root.glassCardBg
              border.color: root.glassBorder
              border.width: 1

              Row {
                id: wsRow
                anchors.centerIn: parent
                spacing: 6
                padding: 4

                Repeater {
                  model: root.workspaceList

                  delegate: Rectangle {
                    id: wsChip
                    required property var modelData

                    readonly property bool isCurrent: modelData.id === root.viewWsId
                    width: chipRow.width + 20
                    height: 30
                    radius: 15

                    color: isCurrent ? root.accentCol : (chipHover.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
                    border.color: isCurrent ? root.accentCol : "transparent"
                    border.width: 1

                    MouseArea {
                      id: chipHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.viewWsId = modelData.id
                        root.rebuild()
                      }
                    }

                    Row {
                      id: chipRow
                      anchors.centerIn: parent
                      spacing: 5

                      Text {
                        textFormat: Text.PlainText
                        font.family: root.monoFont
                        font.pixelSize: Style.font.caption
                        font.bold: wsChip.isCurrent
                        color: wsChip.isCurrent ? Commons.Color.background : root.fg
                        text: "WS " + modelData.id
                      }

                      Text {
                        textFormat: Text.PlainText
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: wsChip.isCurrent ? Commons.Color.background : root.mutedCol
                        text: "(" + modelData.windows.length + ")"
                      }
                    }
                  }
                }
              }
            }
          }

          // ============================================ MOSAIC STAGE (Gnome Overview Grid)
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty state if workspace has no windows
            Item {
              anchors.centerIn: parent
              visible: root.currentWindows.length === 0
              width: 320
              height: 120

              ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.spacing.sm

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  textFormat: Text.PlainText
                  font.family: root.monoFont
                  font.pixelSize: 36
                  color: root.mutedCol
                  text: "󱓻"
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  textFormat: Text.PlainText
                  font.family: root.monoFont
                  font.pixelSize: Style.font.body
                  color: root.mutedCol
                  text: strings.t("empty")
                }
              }
            }

            // Centered Window Mosaic Grid
            Item {
              anchors.fill: parent
              visible: root.currentWindows.length > 0

              GridLayout {
                id: mosaicGrid
                anchors.centerIn: parent

                columns: {
                  var count = root.currentWindows.length
                  if (count <= 1) return 1
                  if (count <= 4) return 2
                  if (count <= 6) return 3
                  return 4
                }

                columnSpacing: 28
                rowSpacing: 28

                Repeater {
                  model: root.currentWindows

                  delegate: Rectangle {
                    id: winTile
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedIndex === index
                    readonly property real winAspect: (modelData.width && modelData.height && modelData.height > 0)
                      ? (modelData.width / modelData.height) : 1.33

                    // Proportional card dimensions preserving true window aspect ratio
                    height: {
                      var count = root.currentWindows.length
                      if (count <= 1) return Math.min(480, stage.height * 0.62)
                      if (count <= 2) return Math.min(360, stage.height * 0.54)
                      if (count <= 4) return Math.min(280, (stage.height - 120) / 2)
                      return Math.min(220, (stage.height - 120) / 2)
                    }

                    width: {
                      var count = root.currentWindows.length
                      var maxW = (count <= 1) ? Math.min(760, stage.width * 0.70)
                               : (count <= 2) ? Math.min(520, (stage.width - 100) / 2)
                               : (count <= 4) ? Math.min(460, (stage.width - 100) / 2)
                               : Math.min(360, (stage.width - 120) / 3)
                      var targetW = (height - 32) * winAspect
                      return Math.max(240, Math.min(maxW, targetW))
                    }

                    radius: 14
                    color: isSelected ? root.glassCardHoverBg : (tileHover.containsMouse ? root.glassCardHoverBg : root.glassCardBg)
                    border.color: isSelected ? root.accentCol : (tileHover.containsMouse ? root.accentCol : root.glassBorder)
                    border.width: isSelected ? 2 : 1

                    scale: isSelected ? 1.02 : (tileHover.containsMouse ? 1.01 : 1.0)
                    Behavior on scale {
                      NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
                    }

                    MouseArea {
                      id: tileHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.activateWindow(modelData)
                      }
                    }

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 8
                      spacing: 6

                      // ---------------- Tile Header Bar
                      RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        spacing: Style.spacing.sm

                        // App Icon
                        Image {
                          Layout.preferredWidth: 18
                          Layout.preferredHeight: 18
                          sourceSize: Qt.size(36, 36)
                          fillMode: Image.PreserveAspectFit
                          source: Quickshell.iconPath(modelData.appClass, true) || Quickshell.iconPath("application-x-executable", true)
                        }

                        // App class & title
                        Text {
                          Layout.fillWidth: true
                          textFormat: Text.PlainText
                          font.family: root.monoFont
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          color: winTile.isSelected ? root.accentCol : root.fg
                          text: (modelData.appClass ? (modelData.appClass + "  •  ") : "") + (modelData.title || "Window")
                          elide: Text.ElideRight
                        }

                        // Close button [✕]
                        Rectangle {
                          Layout.preferredWidth: 22
                          Layout.preferredHeight: 22
                          radius: 11
                          color: closeHover.containsMouse ? Commons.Color.urgent : Qt.rgba(1, 1, 1, 0.12)

                          Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.bold: true
                            color: root.fg
                            text: "✕"
                          }

                          MouseArea {
                            id: closeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root.closeWindow(modelData.address)
                            }
                          }
                        }
                      }

                      // ---------------- Tile Content / Window Preview
                      Rectangle {
                        id: previewBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.40)
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        clip: true

                        // Real live captured window screenshot
                        Image {
                          id: winPreviewImg
                          anchors.fill: parent
                          anchors.margins: 2
                          fillMode: Image.PreserveAspectFit
                          smooth: true
                          mipmap: true
                          asynchronous: true
                          source: Util.fileUrl("/tmp/omarchy-window-previews/" + modelData.cleanAddress + ".jpg")
                          visible: status === Image.Ready
                        }

                        // Glassy Gnome fallback preview when snapshot is not yet available
                        Item {
                          anchors.fill: parent
                          visible: winPreviewImg.status !== Image.Ready

                          Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(1, 1, 1, 0.03)
                          }

                          ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Style.spacing.sm

                            Image {
                              Layout.alignment: Qt.AlignHCenter
                              Layout.preferredWidth: 40
                              Layout.preferredHeight: 40
                              sourceSize: Qt.size(80, 80)
                              fillMode: Image.PreserveAspectFit
                              source: Quickshell.iconPath(modelData.appClass, true) || Quickshell.iconPath("application-x-executable", true)
                            }

                            Text {
                              Layout.alignment: Qt.AlignHCenter
                              textFormat: Text.PlainText
                              font.family: root.monoFont
                              font.pixelSize: Style.font.caption
                              color: root.mutedCol
                              text: modelData.appClass || "App"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ============================================ BOTTOM BAR / HINTS
          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 30
            radius: 15
            color: root.glassCardBg
            border.color: root.glassBorder
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 18
              anchors.rightMargin: 18
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                font.family: root.monoFont
                font.pixelSize: Style.font.caption
                color: root.mutedCol
                text: strings.t("hints")
              }
            }
          }
        }
      }
    }
  }
}
