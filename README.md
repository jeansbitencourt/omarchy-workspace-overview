# Omarchy Workspace Overview

A modern, GNOME-inspired workspace & window overview plugin for [Omarchy](https://omarchy.org) and [Hyprland](https://hyprland.org), built using **Quickshell (Qt 6 / QML)** and Wayland layer-shell.

---

## ✨ Features

- **🪟 Real Live Window Previews**: Captures high-performance snapshots of mapped windows via `grim` instead of showing generic icons.
- **✨ Frosted Glass & Background Blur**: Translucent frosted glass backdrop with compositor blur effect using Hyprland's `layerrule`.
- **🖥️ Simultaneous Multi-Monitor Display**: Opens on all connected monitors at the same time (`eDP-1`, `HDMI-A-1`, etc.), displaying each monitor's respective workspaces and open windows.
- **🎯 Workspace Map**: Shows occupied workspaces plus the active workspace on each monitor, with their windows visible together.
- **🔀 Two Views**: Toggle between the workspace map and a focused view with the active workspace enlarged. The last view is saved in `~/.config/omarchy/workspace-overview.json`.
- **🧩 Adaptive Window Previews**: Workspace cards fill the available canvas based on how many workspaces are visible. Their scrollable thumbnails grow when more space is available.
- **🔍 Quick Search & Filter**: Instant search input pill to filter open windows by window title or application class.
- **🖥️ Multi-Monitor Aware**: Detects active screen focus dynamically, appearing on the display you are currently working on (`eDP-1`, `HDMI-A-1`, etc.).
- **⚡ Dual Triggers**:
  - **Keyboard Shortcut**: `Super + Tab` (customizable via `~/.config/hypr/bindings.lua`).
  - **Mouse Hot Corner**: Slam cursor into the top-left corner (28×28px with 100ms dwell threshold) to toggle the overview.
  - **CLI / IPC**: `omarchy-shell shell toggle jean.workspace-overview`.
- **⌨️ Keyboard Navigation**: Full keyboard control using arrow keys (`Up`/`Down`/`Left`/`Right`), `Tab`, `Enter` to focus, and `Escape` to dismiss.

---

## 📋 Requirements

- **Omarchy Linux** (with `omarchy-shell` / Quickshell >= 0.1.0)
- **Hyprland** with Lua dispatch API enabled
- **`grim`** (for fast screencopy preview snapshots)

---

## 🚀 Installation

### Option 1: One-Line / Automatic Install

Clone the repository and run the installation script:

```bash
git clone https://github.com/jean/omarchy-workspace-overview.git ~/.config/omarchy/plugins/jean.workspace-overview
~/.config/omarchy/plugins/jean.workspace-overview/install.sh
```

### Option 2: Manual Installation

1. **Clone the plugin repository**:
   ```bash
   git clone https://github.com/jean/omarchy-workspace-overview.git ~/.config/omarchy/plugins/jean.workspace-overview
   chmod +x ~/.config/omarchy/plugins/jean.workspace-overview/capture-previews.sh
   ```

2. **Enable the plugin in Omarchy**:
   ```bash
   omarchy plugin enable jean.workspace-overview
   ```

3. **Configure the `Super + Tab` keybinding**:
   Add the following line to `~/.config/hypr/bindings.lua`:
   ```lua
   -- Workspace overview overlay
   o.rebind("SUPER + TAB", "Workspace overview", { panel = "jean.workspace-overview" })
   ```

4. **Enable background blur in Hyprland**:
   Add the layer rule to `~/.config/hypr/looknfeel.lua`:
   ```lua
   layerrule = {
     match = { namespace = "^omarchy-workspace-overview$" },
     blur = true,
     ignore_alpha = 0.05,
     no_anim = true,
   }
   ```

5. **Reload Hyprland & Omarchy Shell**:
   ```bash
   hyprctl reload
   omarchy restart shell
   ```

---

## ⌨️ Shortcuts & Controls

| Action | Control |
|---|---|
| **Toggle Overview** | `Super + Tab` or Mouse into **Top-Left Corner** |
| **Search / Filter** | Type any alphanumeric character |
| **Clear Search** | `Escape` or `Backspace` |
| **Navigate Windows** | `Left` / `Right` / `Up` / `Down` or `Tab` |
| **Select / Focus Window** | `Enter` or `Left Click` on card |
| **Close Window** | Click `✕` button on top-right of window card |
| **Switch Workspace** | Click the arrow on a workspace card, or press `1–9` while the overview is open |
| **Change View** | Click the view button beside search, or press `V` while the overview is open |
| **Dismiss Overview** | `Escape` or click backdrop |

---

## 🛠️ Project Structure

```text
├── manifest.json         # Omarchy shell plugin manifest
├── Overview.qml          # Main fullscreen overlay UI (Search, Workspaces, Mosaic)
├── Service.qml           # Background daemon managing per-screen hot corner surfaces
├── capture-previews.sh   # grim screencopy script saving to /tmp/omarchy-window-previews/
├── install.sh            # Automated installer & Hyprland config validator
├── i18n/                 # Multi-language translation catalogs
│   ├── en.json
│   ├── pt.json
│   └── pt-BR.json
├── AGENTS.md             # AI Agent technical architecture and developer guide
└── README.md             # Project documentation
```

---

## 📄 License

MIT © Jean
