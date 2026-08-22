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

# Offer everything a desktop calls a picture. What Qt cannot decode is
# converted below rather than refused: refusing it would mean explaining which
# formats this particular Qt build happens to ship a plugin for.
chosen=$(omarchy file select --title "Add a wallpaper" \
  --extensions "jpg jpeg png webp bmp gif avif jxl heic tiff tif" 2>/dev/null) || exit 1
[[ -n $chosen && -f $chosen ]] || exit 1

# Qt draws these without a plugin, or with one that is always installed. It has
# no AVIF, JPEG XL or WebP decoder here, and the packaged extras do not add
# one -- so a wallpaper in those formats is a display that draws nothing.
qt_can_draw() {
  case "${1,,}" in
    *.png|*.jpg|*.jpeg|*.bmp|*.gif|*.svg|*.ico) return 0 ;;
    *) return 1 ;;
  esac
}

convert_to_png() {
  local src="$1" dest="$2"
  if command -v magick >/dev/null 2>&1; then magick "$src[0]" "$dest" 2>/dev/null && return 0; fi
  if command -v convert >/dev/null 2>&1; then convert "$src[0]" "$dest" 2>/dev/null && return 0; fi
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$src" -frames:v 1 "$dest" 2>/dev/null && return 0
  fi
  return 1
}

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
converted=""
if ! qt_can_draw "$name"; then
  # Keep the name, change the format: the strip and the renderer both read it
  # through Qt, and neither can be taught a new decoder from here.
  converted="$target_dir/.${RANDOM}.convert.png"
  if ! convert_to_png "$chosen" "$converted"; then
    rm -f "$converted"
    command -v omarchy-notification-send >/dev/null 2>&1 &&
      omarchy-notification-send "Could not convert $name to a format Qt can draw" -t 3000
    exit 1
  fi
  name="${name%.*}.png"
fi

dest="$target_dir/$name"
if [[ -e $dest ]]; then
  stem="${name%.*}"
  ext="${name##*.}"
  for n in $(seq 2 999); do
    dest="$target_dir/$stem-$n.$ext"
    [[ -e $dest ]] || break
  done
fi

if [[ -n $converted ]]; then
  mv -f "$converted" "$dest" || exit 1
else
  # Copied under a temporary name: the folder is one the strip scans, and a
  # half-written file there would be offered as a wallpaper.
  tmp="$target_dir/.${RANDOM}.part"
  trap 'rm -f "$tmp"' EXIT
  cp -- "$chosen" "$tmp" || exit 1
  mv -f "$tmp" "$dest" || exit 1
fi
printf '%s\n' "$dest"
