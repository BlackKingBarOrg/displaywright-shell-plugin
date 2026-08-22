#!/bin/bash
#
# Every picture the arrangement's wallpaper strip can offer, one path per line.
#
# Three sources, in the order they are worth seeing: the folder displaywright
# copies choices into, the current theme's own backgrounds, and the per-theme
# folder Omarchy lets you drop files in. The theme folders are what the stock
# background switcher offers, so the strip is never emptier than the picker it
# is standing in for.

set -uo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
theme=$(cat "$state_home/omarchy/current/theme.name" 2>/dev/null)

dirs=(
  "$HOME/Pictures/Displaywright"
  "$state_home/omarchy/current/theme/backgrounds"
  "$config_home/omarchy/backgrounds/${theme:-none}"
)
search=()
for dir in "${dirs[@]}"; do [[ -d $dir ]] && search+=("$dir"); done
(( ${#search[@]} )) || exit 0

# Only what Qt can actually decode. This build ships plugins for jpeg, gif,
# ico and svg on top of the built-in png and bmp, and has no AVIF, JPEG XL or
# WebP decoder -- listing one would offer a picture that draws as nothing.
# add-wallpaper.sh converts those on the way in instead.
find -L "${search[@]}" -maxdepth 2 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
     -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.svg' \) \
  2>/dev/null | sort -u
