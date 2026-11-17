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

# 3. Select mapped, non-hidden clients on currently active workspaces.
# Capture each toplevel by stableId so overlapping windows are excluded.
windows_data=$(jq -r --argjson aws "$active_ws" '
  .[] | select(.mapped == true and .hidden == false and (.workspace.id as $wid | $aws | index($wid) != null) and .size[0] > 20 and .size[1] > 20)
  | [(.address | sub("^0x"; "")), (.stableId // "")] | join(" ")
' <<< "$clients" 2>/dev/null || true)

if [[ -n "$windows_data" ]]; then
  pids=()
  while read -r clean_addr stable_id; do
    [[ -n "$clean_addr" ]] || continue
    tmp_target="$CACHE_DIR/.tmp_${clean_addr}.jpg"
    target="$CACHE_DIR/${clean_addr}.jpg"
    target_0x="$CACHE_DIR/0x${clean_addr}.jpg"

    # Do not keep a region-captured preview if this client has no toplevel ID.
    if [[ -z "$stable_id" ]]; then
      rm -f "$tmp_target" "$target" "$target_0x" 2>/dev/null || true
      continue
    fi

    (
      if grim -t jpeg -q 75 -T "$stable_id" "$tmp_target" 2>/dev/null && [[ -s "$tmp_target" ]]; then
        mv -f "$tmp_target" "$target"
        ln -sf "$target" "$target_0x" 2>/dev/null || true
      else
        rm -f "$tmp_target" "$target" "$target_0x" 2>/dev/null || true
      fi
    ) &
    pids+=($!)
  done <<< "$windows_data"

  if [[ ${#pids[@]} -gt 0 ]]; then
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done
  fi
fi

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
