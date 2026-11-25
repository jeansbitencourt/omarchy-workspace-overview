# AGENTS.md — Technical Architecture & Agent Developer Guide

This document is intended for AI coding agents and developers maintaining or extending the **Omarchy Workspace Overview** plugin (`jean.workspace-overview`).

---

## 1. System Overview & Technology Stack

- **Target Environment**: [Omarchy](https://omarchy.org) running on Linux with Wayland and [Hyprland](https://hyprland.org).
- **UI Engine**: [Quickshell](https://outfoxxed.me/quickshell/) (Qt 6.7+ QML with Wayland layer-shell protocol bindings).
- **Compositor Control**: Hyprland IPC via `Quickshell.Hyprland` and `hyprctl dispatch` with Lua expressions.
- **Window Capture Backend**: Quickshell ScreencopyView captures each window's Wayland toplevel through Hyprland's toplevel export support.

---

## 2. Directory Layout & Key Files

```
~/.config/omarchy/plugins/jean.workspace-overview/
├── manifest.json         # Plugin metadata, kinds: ["service", "overlay"], entryPoints
├── Service.qml           # Background daemon service for hot-corner surface management
├── Overview.qml          # Fullscreen OverlayWindow (search pill, workspace chips, mosaic cards)
├── install.sh            # Auto-installer and Hyprland configuration updater
├── i18n/                 # Multi-language translation catalog directory
│   ├── en.json
│   ├── pt.json
│   └── pt-BR.json
├── README.md             # End-user documentation
└── AGENTS.md             # This file
```

---

## 3. Architecture & Data Flow

Opening Overview.qml refreshes the Hyprland workspace and toplevel models, then creates one ScreencopyView per window card. Each view captures the window's own toplevel through the Wayland source on its Quickshell Toplevel object. The app icon remains visible until a frame arrives.

Service.qml manages the hot-corner trigger and toggles the overlay. It does not launch background capture processes.

## 4. Critical Technical Constraints & Edge Cases

### A. Hyprland Lua Dispatching
Omarchy's Hyprland configuration uses Lua-based dispatching (`hl.dsp.*`). Calling bare commands such as `workspace 1` or `focuswindow address:...` will fail with syntax errors.
- **Switch Workspace**:
  ```javascript
  Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  ```
- **Focus Window**:
  ```javascript
  Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  ```
- **Close Window**:
  ```javascript
  Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
  ```

### B. Window Identity and Capture Sources

- Quickshell.Hyprland.toplevels.values exposes each window as a Toplevel object with an address and a Wayland capture source.
- Window records retain that object as toplevel; window cards bind ScreencopyView.captureSource to modelData.toplevel?.wayland.
- Normalize addresses for focus and selection keys. No stableId command argument, temporary JPEG cache, address symlink, or local file URL is needed for previews.

### C. Local File URLs in Qt QML
- **Never append query parameters** (like `?v=123`) to `file://` URLs in `QQuickImage`. In Qt Quick, query parameters on local file schemes are treated literally as part of the filename on disk, resulting in `Cannot open: file:///...jpg?v=...`.

### D. Layer Shell Blur

- In ~/.config/hypr/looknfeel.lua, the layer rule should strictly match the overview namespace.
- Keep the hot-corner namespace separate. The corner is nearly transparent and should not receive the overview blur.

### E. Capture Lifecycle

- Window cards create ScreencopyView instances only while the overview is open.
- Set live to false for a single frame and keep the app icon visible while hasContent is false.
- Closing the overview sets each view's captureSource to null, releasing the compositor capture while keeping workspace card data available.
- Previews are captured when the overview opens; Service.qml does not pre-warm them in the background.

### F. Dual-Monitor Geometry
- When dual monitors have different resolutions or vertical offsets (e.g., `eDP-1` at 1366×768 vs `HDMI-A-1` at 1920×1080), `OverlayWindow` dynamically inspects `Hyprland.focusedMonitor` to attach to the active display output.
- The Hot Corner `Variants` in `Service.qml` binds a dedicated `PanelWindow` to each screen in `Quickshell.screens`.

---

## 5. Testing & Verification

1. **Syntax & QML Verification**:
   ```bash
   /usr/lib/qt6/bin/qmllint ~/.config/omarchy/plugins/jean.workspace-overview/Service.qml
   /usr/lib/qt6/bin/qmllint ~/.config/omarchy/plugins/jean.workspace-overview/Overview.qml
   ```
2. **Reloading Omarchy Shell**:
   ```bash
   omarchy restart shell
   ```
3. **Checking Shell Logs**:
   ```bash
   journalctl --user -t omarchy-shell -n 50 --no-pager
   ```
4. **Triggering CLI Toggle**:
   ```bash
   omarchy-shell shell toggle jean.workspace-overview
   ```
5. **Inspecting Hyprland Layer Surfaces**:
   ```bash
   hyprctl layers | grep -i overview
   ```
