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

# Every line here becomes a thumbnail in the strip -- an Image, decoded, in the
# shell's own process. So the walk is bounded before anything expensive runs:
#
#   -H       follows only the three directories named above, never a symlink
#            found inside one, which would otherwise enumerate whatever it
#            points at.
#   awk      drops a path longer than anything real, counts, and exits at the
#            limit. Exiting closes the pipe, so find stops walking rather than
#            finishing a tree nobody will see.
#   sort     therefore never receives more than the cap. It used to run over
#            the whole traversal and `head` applied the limit afterwards, so a
#            large or hostile tree exhausted traversal and sort resources
#            before the advertised cap did anything at all.
MAX_FILES=${DW_MAX_WALLPAPERS:-500}
MAX_PATH=${DW_MAX_PATH:-512}

# Only what Qt can actually decode. This build ships plugins for jpeg, gif,
# ico and svg on top of the built-in png and bmp, and has no AVIF, JPEG XL or
# WebP decoder -- listing one would offer a picture that draws as nothing.
# add-wallpaper.sh converts those on the way in instead.
find -H "${search[@]}" -maxdepth 2 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
     -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.svg' \) \
  2>/dev/null \
  | awk -v maxp="$MAX_PATH" -v maxn="$MAX_FILES" '
      length($0) > maxp { next }
      n >= maxn { stopped = 1; exit }
      { print; n++ }
      END {
        if (stopped)
          print "list-wallpapers: stopped at " maxn " pictures; the rest are not listed" \
            > "/dev/stderr"
      }
    ' \
  | LC_ALL=C sort -u

# find is closed early by design, so the pipeline status says nothing useful.
exit 0
