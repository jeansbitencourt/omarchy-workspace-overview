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
  property string viewMode: "map"
  readonly property string viewModePath: Quickshell.env("HOME") + "/.config/omarchy/workspace-overview.json"

  property var monitorWorkspaces: ({})
  readonly property var workspaceSnapshot: opened ? buildWorkspaceSnapshot() : null

  onWorkspaceSnapshotChanged: {
    if (!workspaceSnapshot) return
    // Replacing a Repeater's array model recreates its delegates.
    var next = Object.assign({}, workspaceSnapshot)
    var changed = Object.keys(next).length !== Object.keys(monitorWorkspaces).length
    for (var name in next) {
      var previous = monitorWorkspaces[name]
      if (previous && previous.length === next[name].length && previous.every(function(ws, i) {
        var candidate = next[name][i]
        return ws.id === candidate.id && ws.isActive === candidate.isActive &&
          sameWindows(ws.windows, candidate.windows)
      })) {
        next[name] = previous
      } else {
        changed = true
      }
    }
    if (changed) monitorWorkspaces = next
  }

  signal requestFocus()

  FileView {
    id: viewModeFile
    path: root.viewModePath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadViewMode()
  }

  function loadViewMode() {
    try {
      var saved = JSON.parse(String(viewModeFile.text() || "{}"))
      if (saved.mode === "map" || saved.mode === "focus") root.viewMode = saved.mode
    } catch (e) {
      // An absent or invalid preference keeps the map as the default.
    }
  }

  function toggleViewMode() {
    root.viewMode = root.viewMode === "map" ? "focus" : "map"
    viewModeFile.setText(JSON.stringify({ mode: root.viewMode }) + "\n")
  }

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

  // Translations
  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function open(payloadJson) {
    root.filterText = ""

    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()

    root.opened = true
    Qt.callLater(function() { root.requestFocus() })
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

  function buildWorkspaceSnapshot() {
    var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []

    var nextWsMonMap = {}
    for (var w = 0; w < workspaces.length; w++) {
      var ws = workspaces[w]
      var mName = ""
      if (ws.monitor) {
        mName = typeof ws.monitor === "string" ? ws.monitor : String(ws.monitor.name || "")
      }
      if (!mName && ws.lastIpcObject && ws.lastIpcObject.monitor) {
        mName = String(ws.lastIpcObject.monitor)
      }
      nextWsMonMap[ws.id] = mName
    }

    var nextWsWinMap = {}

    for (var j = 0; j < toplevels.length; j++) {
      var top = toplevels[j]
      var topWs = top.workspace ? top.workspace.id : -1
      if (topWs <= 0) continue

      var cleanAddr = String(top.address || "").replace(/^0x/, "")
      if (!cleanAddr) continue

      if (!nextWsWinMap[topWs]) nextWsWinMap[topWs] = []
      nextWsWinMap[topWs].push({
        address: "0x" + cleanAddr,
        toplevel: top
      })
    }

    // Organize workspaces per monitor
    var nextMonWorkspaces = {}
    for (var m = 0; m < monitors.length; m++) {
      var mon = monitors[m]
      var curMonName = mon.name
      var monWsList = []

      // Workspaces with windows on this monitor
      for (var wsIdStr in nextWsWinMap) {
        var wsId = parseInt(wsIdStr, 10)
        var wsMon = nextWsMonMap[wsId]
        if (wsMon === curMonName || (!wsMon && Math.floor((wsId - 1) / 10) === mon.id)) {
          monWsList.push({
            id: wsId,
            isActive: mon.activeWorkspace && mon.activeWorkspace.id === wsId,
            windows: nextWsWinMap[wsId]
          })
        }
      }

      monWsList.sort(function(a, b) { return a.id - b.id })

      // Keep the active workspace visible even when it has no windows.
      var actId = mon.activeWorkspace ? mon.activeWorkspace.id : (mon.id * 10 + 1)
      if (!monWsList.some(function(ws) { return ws.id === actId })) {
        monWsList.push({
          id: actId,
          isActive: true,
          windows: []
        })
        monWsList.sort(function(a, b) { return a.id - b.id })
      }

      nextMonWorkspaces[curMonName] = monWsList
    }

    return nextMonWorkspaces
  }

  function sameWindows(previous, next) {
    return previous.length === next.length && previous.every(function(win, i) {
      return win.address === next[i].address && win.toplevel === next[i].toplevel
    })
  }

  function windowTitle(win) {
    var top = win.toplevel
    return top ? String(top.title || (top.wayland ? top.wayland.title : "") || "") : ""
  }

  function windowClass(win) {
    var top = win.toplevel
    return top ? String((top.lastIpcObject || {}).class || (top.wayland ? top.wayland.appId : "") || "") : ""
  }

  function matchesWindow(win, query) {
    return query === "" || windowTitle(win).toLowerCase().includes(query) ||
      windowClass(win).toLowerCase().includes(query)
  }

  function activateWindow(win) {
    if (!win || !win.address) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + win.address + '" })')
    root.dismiss()
  }

  function focusWorkspace(id) {
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }

  function closeWindow(address) {
    if (!address) return
    Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
    Qt.callLater(function() {
      Hyprland.refreshToplevels()
    })
  }

  // Multi-Monitor Overview surfaces: one PanelWindow per connected display
  Variants {
    id: screenPanels
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: panelWin
        required property var modelData

        screen: modelData
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-workspace-overview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: isFocusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
        readonly property string monName: hyprMonitor ? String(hyprMonitor.name || "") : (modelData ? modelData.name : "")
        readonly property bool isFocusedScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === monName

        property int selectedIndex: 0
        property var previousWindows: []
        property bool contentRevealed: false

        onVisibleChanged: {
          if (visible) {
            selectedIndex = 0
            contentRevealed = false
            Qt.callLater(function() {
              panelWin.contentRevealed = true
              if (panelWin.isFocusedScreen) keyCatcher.forceActiveFocus()
            })
          } else {
            contentRevealed = false
          }
        }

        Connections {
          target: root
          function onRequestFocus() {
            if (panelWin.isFocusedScreen) {
              keyCatcher.forceActiveFocus()
            }
          }
        }

        readonly property var screenWorkspaces: (root.monitorWorkspaces && root.monitorWorkspaces[monName]) ? root.monitorWorkspaces[monName] : []
        readonly property var displayedWorkspaces: {
          if (root.viewMode !== "focus") return screenWorkspaces
          var ordered = screenWorkspaces.slice()
          ordered.sort(function(a, b) {
            if (a.isActive !== b.isActive) return a.isActive ? -1 : 1
            return a.id - b.id
          })
          return ordered
        }

        readonly property var currentWindows: {
          var filterLower = root.filterText.toLowerCase().trim()
          var matches = []
          for (var i = 0; i < screenWorkspaces.length; i++) {
            var windows = screenWorkspaces[i].windows
            for (var j = 0; j < windows.length; j++) {
              var win = windows[j]
              if (root.matchesWindow(win, filterLower)) {
                matches.push(win)
              }
            }
          }
          return matches
        }

        onCurrentWindowsChanged: {
          var selected = previousWindows[selectedIndex]
          var index = selected ? currentWindows.findIndex(function(win) {
            return win.address === selected.address
          }) : -1
          selectedIndex = index >= 0 ? index : Math.max(0, Math.min(selectedIndex, currentWindows.length - 1))
          previousWindows = currentWindows
        }

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

          opacity: panelWin.contentRevealed ? 1 : 0
          scale: panelWin.contentRevealed ? 1 : 0.98
          Behavior on opacity {
            NumberAnimation {
              duration: Style.duration(160)
              easing.type: Easing.OutCubic
            }
          }
          Behavior on scale {
            NumberAnimation {
              duration: Style.duration(160)
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
            focus: panelWin.isFocusedScreen

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText.length > 0) {
                  root.filterText = ""
                } else {
                  root.dismiss()
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                if (panelWin.currentWindows.length > 0) {
                  if (event.modifiers & Qt.ShiftModifier) {
                    panelWin.selectedIndex = (panelWin.selectedIndex - 1 + panelWin.currentWindows.length) % panelWin.currentWindows.length
                  } else {
                    panelWin.selectedIndex = (panelWin.selectedIndex + 1) % panelWin.currentWindows.length
                  }
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                if (panelWin.currentWindows.length > 0) {
                  panelWin.selectedIndex = (panelWin.selectedIndex - 1 + panelWin.currentWindows.length) % panelWin.currentWindows.length
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (panelWin.currentWindows.length > 0 && panelWin.selectedIndex >= 0 && panelWin.selectedIndex < panelWin.currentWindows.length) {
                  root.activateWindow(panelWin.currentWindows[panelWin.selectedIndex])
                }
                event.accepted = true
              } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && root.filterText.length === 0) {
                var targetWs = event.key - Qt.Key_0
                root.focusWorkspace(targetWs)
                root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_V && root.filterText.length === 0 && !event.modifiers) {
                root.toggleViewMode()
                event.accepted = true
              } else if (event.key === Qt.Key_Backspace) {
                if (root.filterText.length > 0) {
                  root.filterText = root.filterText.substring(0, root.filterText.length - 1)
                  event.accepted = true
                }
              } else if (event.text && event.text.length === 1 && !event.modifiers) {
                root.filterText += event.text
                event.accepted = true
              }
            }

            ColumnLayout {
              anchors.fill: parent
              spacing: 20

              // ============================================ TOP HEADER
              RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

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

                Rectangle {
                  implicitWidth: modeLabel.implicitWidth + 28
                  implicitHeight: 38
                  radius: 19
                  color: root.glassCardBg
                  border.color: root.accentCol
                  border.width: 1
                  Text {
                    id: modeLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.viewMode === "map" ? strings.t("modeMap") : strings.t("modeFocus")
                    color: root.fg
                    font.family: root.monoFont
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleViewMode()
                  }
                }
              }

              // All workspaces and their windows share the same canvas.
              Flickable {
                id: workspaceScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: workspaceGrid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                  id: workspaceGrid
                  width: workspaceScroll.width
                  readonly property int mapColumns: {
                    var count = panelWin.displayedWorkspaces.length
                    if (count <= 1) return 1
                    if (count <= 4) return width >= 850 ? 2 : 1
                    return width >= 1500 ? 3 : (width >= 850 ? 2 : 1)
                  }
                  readonly property int mapRows: Math.max(1, Math.ceil(panelWin.displayedWorkspaces.length / mapColumns))
                  readonly property real mapCardHeight: Math.max(220,
                    (workspaceScroll.height - (mapRows - 1) * rowSpacing) / mapRows)
                  columns: root.viewMode === "focus" ? (panelWin.displayedWorkspaces.length > 1 ? 2 : 1)
                    : mapColumns
                  columnSpacing: 18
                  rowSpacing: 18

                  Repeater {
                    model: panelWin.displayedWorkspaces

                    delegate: Rectangle {
                      id: workspaceCard
                      required property var modelData
                      property var matchingWindows: []
                      readonly property var filteredWindows: {
                        var query = root.filterText.toLowerCase().trim()
                        return query === "" ? modelData.windows : modelData.windows.filter(function(win) {
                          return root.matchesWindow(win, query)
                        })
                      }
                      function updateMatchingWindows() {
                        // A live title can change while the search still matches the same windows.
                        if (!root.sameWindows(matchingWindows, filteredWindows)) matchingWindows = filteredWindows
                      }
                      onFilteredWindowsChanged: updateMatchingWindows()
                      Component.onCompleted: updateMatchingWindows()
                      readonly property int tileColumns: {
                        var count = matchingWindows.length
                        if (count <= 1 || width < 350) return 1
                        if (count <= 4 || width < 650) return 2
                        return 3
                      }
                      readonly property real tileWidth: (width - 32 - (tileColumns - 1) * 10) / tileColumns
                      readonly property int tileRows: Math.max(1, Math.ceil(matchingWindows.length / tileColumns))
                      readonly property real tileHeight: Math.max(100, Math.min(tileWidth * 0.72,
                        (height - 88 - (tileRows - 1) * 10) / tileRows))

                      Layout.preferredWidth: root.viewMode === "focus" && panelWin.displayedWorkspaces.length > 1
                        ? (modelData.isActive ? workspaceGrid.width * 0.68 - 9 : workspaceGrid.width * 0.32 - 9)
                        : (workspaceGrid.width - (workspaceGrid.columns - 1) * workspaceGrid.columnSpacing) / workspaceGrid.columns
                      Layout.preferredHeight: root.viewMode === "focus"
                        ? (modelData.isActive ? Math.max(360, workspaceScroll.height - 4) : Math.max(145, Math.min(220, workspaceScroll.height * 0.28)))
                        : workspaceGrid.mapCardHeight
                      Layout.rowSpan: root.viewMode === "focus" && modelData.isActive
                        ? Math.max(1, panelWin.displayedWorkspaces.length - 1) : 1
                      radius: 16
                      color: root.glassCardBg
                      border.color: modelData.isActive ? root.accentCol : root.glassBorder
                      border.width: modelData.isActive ? 2 : 1
                      clip: true

                      ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        RowLayout {
                          Layout.fillWidth: true
                          Layout.preferredHeight: 28
                          spacing: 8

                          Text {
                            textFormat: Text.PlainText
                            text: "WS " + workspaceCard.modelData.id
                            color: workspaceCard.modelData.isActive ? root.accentCol : root.fg
                            font.family: root.monoFont
                            font.pixelSize: 16
                            font.bold: true
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: workspaceCard.modelData.isActive ? strings.t("active") : ""
                            color: root.accentCol
                            font.family: root.monoFont
                            font.pixelSize: Style.font.caption
                          }
                          Item { Layout.fillWidth: true }
                          Text {
                            textFormat: Text.PlainText
                            text: strings.tn("windows", workspaceCard.modelData.windows.length).arg(workspaceCard.modelData.windows.length)
                            color: root.mutedCol
                            font.family: root.monoFont
                            font.pixelSize: Style.font.caption
                          }
                          Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: wsButtonHover.containsMouse ? root.glassCardHoverBg : "transparent"
                            border.color: root.glassBorder
                            Text { anchors.centerIn: parent; text: "↗"; color: root.fg; font.pixelSize: 16 }
                            MouseArea {
                              id: wsButtonHover
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: { root.focusWorkspace(workspaceCard.modelData.id); root.dismiss() }
                            }
                          }
                        }

                        Item {
                          Layout.fillWidth: true
                          Layout.fillHeight: true

                          Flickable {
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: windowGrid.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            visible: workspaceCard.matchingWindows.length > 0

                            GridLayout {
                            id: windowGrid
                            width: parent.width
                            columns: workspaceCard.tileColumns
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                              model: workspaceCard.matchingWindows
                              delegate: Rectangle {
                                id: winTile
                                required property var modelData
                                readonly property string appClass: root.windowClass(modelData)
                                readonly property bool isSelected: panelWin.currentWindows.length > panelWin.selectedIndex &&
                                  panelWin.currentWindows[panelWin.selectedIndex].address === modelData.address
                                Layout.preferredWidth: workspaceCard.tileWidth
                                Layout.preferredHeight: workspaceCard.tileHeight
                                radius: 10
                                color: root.glassCardHoverBg
                                border.color: isSelected ? root.accentCol : root.glassBorder
                                border.width: isSelected ? 2 : 1
                                clip: true

                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: root.activateWindow(modelData)
                                }
                                Item {
                                  id: previewFrame
                                  anchors.fill: parent
                                  anchors.margins: 5
                                  anchors.bottomMargin: 28

                                  ScreencopyView {
                                    id: previewCapture
                                    anchors.centerIn: parent
                                    captureSource: root.opened ? (modelData.toplevel?.wayland ?? null) : null
                                    constraintSize: Qt.size(parent.width, parent.height)
                                    live: false
                                    paintCursor: false
                                    visible: hasContent
                                  }
                                  Image {
                                    anchors.centerIn: parent
                                    width: 32
                                    height: 32
                                    visible: !previewCapture.hasContent
                                    source: Quickshell.iconPath(winTile.appClass, true) || Quickshell.iconPath("application-x-executable", true)
                                  }
                                }
                                RowLayout {
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  anchors.bottom: parent.bottom
                                  anchors.margins: 7
                                  height: 22
                                  spacing: 5
                                  Image {
                                    Layout.preferredWidth: 15
                                    Layout.preferredHeight: 15
                                    source: Quickshell.iconPath(winTile.appClass, true) || Quickshell.iconPath("application-x-executable", true)
                                  }
                                  Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: root.windowTitle(winTile.modelData) || winTile.appClass
                                    elide: Text.ElideRight
                                    color: root.fg
                                    font.family: root.bodyFont
                                    font.pixelSize: Style.font.caption
                                  }
                                  Text {
                                    text: "×"
                                    color: root.mutedCol
                                    font.pixelSize: 18
                                    MouseArea {
                                      anchors.fill: parent
                                      cursorShape: Qt.PointingHandCursor
                                      onClicked: root.closeWindow(modelData.address)
                                    }
                                  }
                                }
                              }
                            }
                            }
                          }

                          Text {
                            anchors.centerIn: parent
                            visible: workspaceCard.matchingWindows.length === 0
                            textFormat: Text.PlainText
                            text: root.filterText.length > 0 ? strings.t("noMatches") : strings.t("empty")
                            color: root.mutedCol
                            font.family: root.monoFont
                            font.pixelSize: Style.font.body
                          }
                        }
                      }
                    }
                  }
                }
              }

              // ============================================ BOTTOM BAR (Quick Tips)
              Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: 28
                implicitWidth: hintRow.width + 24
                radius: 14
                color: root.glassCardBg
                border.color: root.glassBorder
                border.width: 1

                Row {
                  id: hintRow
                  anchors.centerIn: parent
                  spacing: Style.spacing.md

                  Text {
                    textFormat: Text.PlainText
                    font.family: root.monoFont
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                    text: strings.t("hints") + "  •  [V] " + strings.t("toggleMode")
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
