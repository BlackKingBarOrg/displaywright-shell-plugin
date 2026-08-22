#!/bin/bash
#
# Take one picture out of the wallpaper folder.
#
# Only out of *that* folder: the strip also lists the current theme's
# backgrounds, and those belong to the theme. Deleting one would damage
# something this tool did not install and cannot put back.
#
# Trashed rather than deleted where the desktop has a trash, because "remove"
# in a wallpaper picker should not mean "gone".

set -uo pipefail

target="${1:-}"
[[ -n $target ]] || { echo "usage: remove-wallpaper.sh <path>" >&2; exit 2; }

owned="$HOME/Pictures/Displaywright"

# Resolved before comparing: a path with .. in it would otherwise walk out of
# the folder while still looking like it starts inside one.
real=$(readlink -f -- "$target" 2>/dev/null) || exit 1
owned_real=$(readlink -f -- "$owned" 2>/dev/null) || exit 1

case "$real/" in
  "$owned_real"/*) ;;
  *) echo "remove-wallpaper: $target is not in $owned" >&2; exit 3 ;;
esac

[[ -f $real ]] || exit 0        # already gone; nothing to report

if command -v gio >/dev/null 2>&1 && gio trash -- "$real" 2>/dev/null; then
  exit 0
fi
rm -f -- "$real"
