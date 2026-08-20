#!/bin/bash
#
# Pick a wallpaper for one display, using Omarchy's own image picker.
#
# Double-clicking a display's background runs this with that display's name.
# It gathers candidate pictures, hands them to `omarchy-shell image-selector`
# -- the same overlay the stock background switcher uses, so it looks and
# behaves like the rest of the desktop -- and writes whatever comes back into
# the one output's entry in wallpapers.json.
#
# The renderer watches that file, so the wallpaper is on screen before this
# script exits. Writing goes through a temporary file and a rename: the reader
# is another process, and half a config is a display drawing nothing.

set -uo pipefail

output="${1:-}"
[[ -n $output ]] || { echo "usage: pick-wallpaper.sh <output-name>" >&2; exit 2; }

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
config="$config_home/displaywright/wallpapers.json"
stock_thumbnails="$cache_home/omarchy/image-selector"

note() { command -v omarchy-notification-send >/dev/null 2>&1 &&
  omarchy-notification-send "$1" -t 2500 || notify-send -a Displaywright Displaywright "$1"; }

command -v jq >/dev/null 2>&1 || { note "jq is required to set a wallpaper"; exit 1; }

# Where to look for pictures: the folder the Displaywright app copies into, the
# current theme's own backgrounds, and the per-theme folder Omarchy lets you
# drop files into. The theme folders are what the stock switcher offers, so the
# grid is never emptier than the one this replaces.
theme_name=$(cat "$state_home/omarchy/current/theme.name" 2>/dev/null)
dirs=(
  "$HOME/Pictures/Displaywright"
  "$state_home/omarchy/current/theme/backgrounds"
  "$config_home/omarchy/backgrounds/${theme_name:-none}"
)
search=()
for dir in "${dirs[@]}"; do [[ -d $dir ]] && search+=("$dir"); done
(( ${#search[@]} )) || { note "No pictures found for $output"; exit 0; }

# Omarchy keeps thumbnails for everything its own picker has shown. Reuse one
# when it is there and fall back to the picture itself, which the picker scales
# on the fly -- slower to open, but never an empty grid.
thumbnail_for() {
  local media="$1" signature hash
  if [[ -s $stock_thumbnails/index.tsv ]]; then
    signature=$(stat -Lc '%s:%Y' "$media" 2>/dev/null) || { printf '%s' "$media"; return; }
    hash=$(awk -F '\t' -v path="$media" -v sig="$signature" \
      '$1 == path && $2 == sig { print $3; exit }' "$stock_thumbnails/index.tsv" 2>/dev/null)
    if [[ -n $hash && -f $stock_thumbnails/$hash.jpg ]]; then
      printf '%s' "$stock_thumbnails/$hash.jpg"
      return
    fi
  fi
  printf '%s' "$media"
}

rows_file=$(mktemp) selection_file=$(mktemp) done_file=$(mktemp)
trap 'rm -f "$rows_file" "$selection_file" "$done_file"' EXIT
rm -f "$done_file"

while IFS= read -r -d '' media; do
  printf '%s\t%s\n' "$media" "$(thumbnail_for "$media")"
done < <(find -L "${search[@]}" -maxdepth 2 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
     -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.avif' -o -iname '*.jxl' \) \
  -print0 2>/dev/null | sort -z) | sort -u >"$rows_file"

[[ -s $rows_file ]] || { note "No pictures found for $output"; exit 0; }

# Preselect what this display is already showing, so the picker opens on it.
selected=$(jq -r --arg o "$output" '.monitors[$o].path // ""' "$config" 2>/dev/null)

rows_b64=$(base64 -w 0 <"$rows_file")
if [[ $(omarchy-shell image-selector open "" "$rows_b64" "$selected" \
        "$selection_file" "$done_file" false false 2>/dev/null) != ok ]]; then
  note "Could not open the picker"
  exit 1
fi

# The picker touches done_file when it closes, whether or not anything was
# chosen. Give up rather than spin forever if the shell dies mid-pick.
for _ in $(seq 1 6000); do [[ -e $done_file ]] && break; sleep 0.05; done
[[ -e $done_file ]] || exit 1
[[ -s $selection_file ]] || exit 0          # cancelled; leave the display alone
picked=$(<"$selection_file")
[[ -n $picked && -f $picked ]] || exit 0

mkdir -p "$(dirname "$config")"
[[ -f $config ]] || printf '{"version":1,"monitors":{}}\n' >"$config"

# A span covers every display and outranks the per-display entries, so writing
# one while a span is set would look like the pick did nothing at all. Choosing
# a picture for one display is a decision to stop spanning.
had_span=$(jq -r 'if .span then "yes" else "no" end' "$config" 2>/dev/null)

tmp="$config.tmp.$$"
if jq --arg o "$output" --arg p "$picked" \
     '.version = 1
      | del(.span)
      | .monitors = ((.monitors // {}) | .[$o] = ((.[$o] // {})
          | .kind = "image" | .path = $p | .fit = (.fit // "fill")))' \
     "$config" >"$tmp" 2>/dev/null && [[ -s $tmp ]]; then
  mv -f "$tmp" "$config"
else
  rm -f "$tmp"
  note "Could not update $config"
  exit 1
fi

[[ $had_span == yes ]] && note "Stopped spanning: $output now has its own wallpaper"

# The renderer watches the file, so this only saves it the watch latency.
omarchy-shell displaywright reload >/dev/null 2>&1 || true
