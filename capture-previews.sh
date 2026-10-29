#!/bin/bash
set -euo pipefail

GEN="${1:-}"
CACHE_DIR="/tmp/omarchy-window-previews"
mkdir -p "$CACHE_DIR"

clients=$(hyprctl clients -j 2>/dev/null || echo "[]")

if [[ -z "$clients" || "$clients" == "null" ]]; then
  exit 0
fi

# Select all mapped, non-hidden clients with valid geometry on real workspaces (> 0)
visible=$(jq -c '[.[] | select(.mapped == true and .hidden == false and .workspace.id > 0 and .size[0] > 20 and .size[1] > 20)]' <<< "$clients" 2>/dev/null || echo "[]")
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
    grim -t jpeg -q 75 -g "${x},${y} ${w}x${h}" "$target" 2>/dev/null || true
    ln -sf "$target" "$target_0x" 2>/dev/null || true
    if [[ -n "$GEN" ]]; then
      ln -sf "$target" "$CACHE_DIR/${clean_addr}_${GEN}.jpg" 2>/dev/null || true
      ln -sf "$target" "$CACHE_DIR/0x${clean_addr}_${GEN}.jpg" 2>/dev/null || true
    fi
  fi
done

# Clean up older generations
if [[ -n "$GEN" && "$GEN" =~ ^[0-9]+$ && "$GEN" -gt 2 ]]; then
  old=$((GEN - 2))
  rm -f "$CACHE_DIR"/*_"${old}".jpg 2>/dev/null || true
fi
