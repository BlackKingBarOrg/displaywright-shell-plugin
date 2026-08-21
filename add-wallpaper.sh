#!/bin/bash
#
# Pick a picture from anywhere on disk and keep it.
#
# The file is copied into ~/Pictures/Displaywright rather than referenced where
# it sits: a wallpaper that breaks when you empty ~/Downloads is not much of a
# wallpaper. The copy goes through a temporary name so the folder the strip
# scans never shows a half-written file. Prints the resulting path.

set -uo pipefail

target_dir="$HOME/Pictures/Displaywright"

chosen=$(omarchy file select --title "Add a wallpaper" \
  --extensions "jpg jpeg png webp bmp gif avif jxl" 2>/dev/null) || exit 1
[[ -n $chosen && -f $chosen ]] || exit 1

# Already somewhere the strip lists: use it where it is.
case "$chosen" in
  "$target_dir"/*) printf '%s\n' "$chosen"; exit 0 ;;
esac

mkdir -p "$target_dir"

# The same picture picked twice should not become two files.
for existing in "$target_dir"/*; do
  [[ -f $existing ]] || continue
  if cmp -s "$chosen" "$existing"; then printf '%s\n' "$existing"; exit 0; fi
done

name=$(basename -- "$chosen")
dest="$target_dir/$name"
if [[ -e $dest ]]; then
  stem="${name%.*}"
  ext="${name##*.}"
  for n in $(seq 2 999); do
    dest="$target_dir/$stem-$n.$ext"
    [[ -e $dest ]] || break
  done
fi

tmp="$target_dir/.${RANDOM}.part"
trap 'rm -f "$tmp"' EXIT
cp -- "$chosen" "$tmp" || exit 1
mv -f "$tmp" "$dest" || exit 1
printf '%s\n' "$dest"
