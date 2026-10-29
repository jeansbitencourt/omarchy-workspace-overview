#!/bin/bash
set -euo pipefail

CACHE_DIR="/tmp/omarchy-window-previews"
mkdir -p "$CACHE_DIR"

# 1. Never capture while the overview overlay is mapped on screen
if hyprctl layers 2>/dev/null | grep -q "omarchy-workspace-overview"; then
  exit 0
fi

clients=$(hyprctl clients -j 2>/dev/null || echo "[]")
if [[ -z "$clients" || "$clients" == "null" || "$clients" == "[]" ]]; then
  exit 0
fi

monitors=$(hyprctl monitors -j 2>/dev/null || echo "[]")
if [[ -z "$monitors" || "$monitors" == "null" || "$monitors" == "[]" ]]; then
  exit 0
fi

# 2. Find active workspace IDs across all connected monitors
active_ws=$(jq -c '[.[].activeWorkspace.id] | unique' <<< "$monitors" 2>/dev/null || echo "[]")

# 3. Select ONLY mapped, non-hidden clients with valid geometry on the currently active workspaces
visible=$(jq -c --argjson aws "$active_ws" '[.[] | select(.mapped == true and .hidden == false and (.workspace.id as $wid | $aws | index($wid) != null) and .size[0] > 20 and .size[1] > 20)]' <<< "$clients" 2>/dev/null || echo "[]")
count=$(jq 'length' <<< "$visible" 2>/dev/null || echo 0)

for ((i=0; i<count; i++)); do
  addr=$(jq -r ".[$i].address" <<< "$visible")
  clean_addr="${addr#0x}"
  x=$(jq -r ".[$i].at[0]" <<< "$visible")
  y=$(jq -r ".[$i].at[1]" <<< "$visible")
  w=$(jq -r ".[$i].size[0]" <<< "$visible")
  h=$(jq -r ".[$i].size[1]" <<< "$visible")
  if [[ -n "$addr" && -n "$x" && -n "$y" && -n "$w" && -n "$h" ]]; then
    target="$CACHE_DIR/${clean_addr}.jpg"
    target_0x="$CACHE_DIR/0x${clean_addr}.jpg"
    tmp_target="$CACHE_DIR/.tmp_${clean_addr}.jpg"
    if grim -t jpeg -q 75 -g "${x},${y} ${w}x${h}" "$tmp_target" 2>/dev/null && [[ -s "$tmp_target" ]]; then
      mv -f "$tmp_target" "$target"
      ln -sf "$target" "$target_0x" 2>/dev/null || true
    else
      rm -f "$tmp_target" 2>/dev/null || true
    fi
  fi
done

# 4. Clean up stale previews for windows that no longer exist
all_clean_addrs=$(jq -r '.[].address | sub("^0x"; "")' <<< "$clients" 2>/dev/null || echo "")
if [[ -n "$all_clean_addrs" ]]; then
  shopt -s nullglob
  for f in "$CACHE_DIR"/*.jpg; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f" .jpg)
    base="${base#0x}"
    # Ignore temporary files
    [[ "$base" =~ ^\.tmp ]] && continue
    if ! grep -q -Fx "$base" <<< "$all_clean_addrs"; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
  shopt -u nullglob
fi
