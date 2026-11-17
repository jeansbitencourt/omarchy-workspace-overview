# AGENTS.md — Technical Architecture & Agent Developer Guide

This document is intended for AI coding agents and developers maintaining or extending the **Omarchy Workspace Overview** plugin (`jean.workspace-overview`).

---

## 1. System Overview & Technology Stack

- **Target Environment**: [Omarchy](https://omarchy.org) running on Linux with Wayland and [Hyprland](https://hyprland.org).
- **UI Engine**: [Quickshell](https://outfoxxed.me/quickshell/) (Qt 6.7+ QML with Wayland layer-shell protocol bindings).
- **Compositor Control**: Hyprland IPC via `Quickshell.Hyprland` and `hyprctl dispatch` with Lua expressions.
- **Window Capture Backend**: `grim -T` captures individual toplevels using Hyprland's toplevel export support.

---

## 2. Directory Layout & Key Files

```
~/.config/omarchy/plugins/jean.workspace-overview/
├── manifest.json         # Plugin metadata, kinds: ["service", "overlay"], entryPoints
├── Service.qml           # Background daemon service for hot-corner surface management
├── Overview.qml          # Fullscreen OverlayWindow (search pill, workspace chips, mosaic cards)
├── capture-previews.sh   # Screencopy snapshot generator
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

```
   [User Input]
   ├─ Super+Tab (Hyprland Lua Binding) ──┐
   ├─ Top-Left Corner (Service.qml)    ──┼──> omarchy-shell shell toggle jean.workspace-overview
   └─ CLI / IPC                        ──┘               │
                                                         ▼
                                                [Overview.qml: open()]
                                                         │
                                    ┌────────────────────┴────────────────────┐
                                    ▼                                         ▼
                        [capture-previews.sh]                       [Hyprland IPC Query]
                     Runs grim -T per mapped                      Fetches active workspaces
                     toplevel using its stableId                    and window toplevel list
                                    │                                         │
                                    └────────────────────┬────────────────────┘
                                                         ▼
                                            [OverlayWindow Rendered]
                                           - Frosted glass + Blur
                                           - Top Search Pill
                                           - Active Workspaces Row
                                           - Aspect-Preserving Mosaic
```

---

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

### B. Address Formatting & Normalization
- `Quickshell.Hyprland.toplevels.values` exposes window addresses **without** the `0x` prefix (e.g. `5586969bdfb0`).
- `lastIpcObject.address` and `hyprctl clients` often include the `0x` prefix (e.g. `0x5586969bdfb0`).
- `hyprctl clients -j` provides each window's `stableId`, which `capture-previews.sh` passes to `grim -T`; addresses remain the cache filenames and QML lookup keys.
- To prevent missing preview images, `capture-previews.sh` creates symlinks in `/tmp/omarchy-window-previews/` for **both** address representations (`0x<addr>.jpg` and `<addr>.jpg`).
- In QML, `cleanAddress` strips any leading `0x` to ensure consistent file URLs.

### C. Local File URLs in Qt QML
- **Never append query parameters** (like `?v=123`) to `file://` URLs in `QQuickImage`. In Qt Quick, query parameters on local file schemes are treated literally as part of the filename on disk, resulting in `Cannot open: file:///...jpg?v=...`.

### D. Layer Shell Blur & Screencopy Deadlocks
- In `~/.config/hypr/looknfeel.lua`, the layer rule **must strictly match** the overlay namespace:
  ```lua
  match = { namespace = "^omarchy-workspace-overview$" }
  ```
- **Do not use a wildcard** like `^omarchy-workspace-overview.*`. The hot corner in `Service.qml` uses the namespace `omarchy-overview-hotcorner`. If blur is applied to a transparent 28×28px overlay window, wlroots screencopy (`grim`) hangs or stalls waiting for frame damages.

### E. Capture Sequence Timing
- The current open flow starts `capture-previews.sh` before `OverlayWindow` maps. `grim -T` targets a specific toplevel, so other windows and the overview backdrop do not enter that window's image.
- `openSafetyTimer` (180ms fallback) ensures that even if `grim` takes longer or fails, the overlay opens without stranding the user.

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
