#!/usr/bin/env bash
set -euo pipefail

# Plugin installation script for Omarchy
PLUGIN_ID="jean.workspace-overview"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing $PLUGIN_ID into Omarchy..."

# If not already located at TARGET_DIR, copy or symlink
if [[ "$SCRIPT_DIR" != "$TARGET_DIR" ]]; then
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -e "$TARGET_DIR" ]]; then
    echo "Backing up existing plugin at $TARGET_DIR..."
    mv "$TARGET_DIR" "${TARGET_DIR}.bak.$(date +%s)"
  fi
  cp -r "$SCRIPT_DIR" "$TARGET_DIR"
  echo "Copied plugin to $TARGET_DIR"
fi

# Ensure capture script is executable
chmod +x "$TARGET_DIR/capture-previews.sh"

# Enable plugin in Omarchy
echo "==> Enabling plugin in omarchy..."
omarchy plugin enable "$PLUGIN_ID" || true

# Check keybinding in ~/.config/hypr/bindings.lua
BINDINGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
if [[ -f "$BINDINGS_FILE" ]]; then
  if ! grep -q "jean.workspace-overview" "$BINDINGS_FILE"; then
    echo "==> Adding SUPER+TAB keybinding to $BINDINGS_FILE..."
    cat << 'EOF' >> "$BINDINGS_FILE"

-- Workspace overview overlay
o.rebind("SUPER + TAB", "Workspace overview", { panel = "jean.workspace-overview" })
EOF
  else
    echo "==> Keybinding already present in $BINDINGS_FILE"
  fi
fi

# Check blur rule in ~/.config/hypr/looknfeel.lua
LOOKNFEEL_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/looknfeel.lua"
if [[ -f "$LOOKNFEEL_FILE" ]]; then
  if ! grep -q "omarchy-workspace-overview" "$LOOKNFEEL_FILE"; then
    echo "==> Adding layer blur rule to $LOOKNFEEL_FILE..."
    cat << 'EOF' >> "$LOOKNFEEL_FILE"

-- Blur for Workspace Overview overlay
layerrule = {
  match = { namespace = "^omarchy-workspace-overview$" },
  blur = true,
  ignore_alpha = 0.05,
  no_anim = true,
}
EOF
  else
    echo "==> Layer blur rule already present in $LOOKNFEEL_FILE"
  fi
fi

# Reload Hyprland & Shell
echo "==> Reloading Hyprland configuration..."
hyprctl reload >/dev/null 2>&1 || true

echo "==> Restarting Omarchy Shell..."
omarchy restart shell

echo ""
echo "✅ Installation complete! You can open the overview with SUPER+TAB or moving the cursor to the top-left hot corner."
