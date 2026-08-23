#!/usr/bin/env bash
#
# Adds the two things a plugin is not allowed to add for itself: a row in the
# Omarchy menu, and a keybinding.
#
# Omarchy's manifest has no field for either, and `omarchy plugin add` runs
# nothing from inside a plugin -- deliberately. It refuses a plugin folder that
# contains so much as a symlink, because a plugin lands in a trusted directory
# and is not itself trusted. So this is a command you run once, by hand, and it
# tells you exactly what it changed.
#
#   ~/.config/omarchy/plugins/ai.bkblab.displaywright/install-shortcuts.sh
#   ~/.config/omarchy/plugins/ai.bkblab.displaywright/install-shortcuts.sh --remove
#
# Both files are edited between markers, so running it twice changes nothing
# and --remove takes out exactly what was added.

set -euo pipefail

PLUGIN_ID="ai.bkblab.displaywright"
ACTION="omarchy-shell shell toggle ${PLUGIN_ID} '{}'"

BINDINGS="${HYPR_BINDINGS:-$HOME/.config/hypr/bindings.lua}"
MENU="${OMARCHY_MENU_EXT:-$HOME/.config/omarchy/extensions/omarchy-menu.jsonc}"

BEGIN="-- >>> displaywright (managed) >>>"
END="-- <<< displaywright <<<"
JBEGIN="// >>> displaywright (managed) >>>"
JEND="// <<< displaywright <<<"

# Tried in order. The first one nothing else has wins.
CANDIDATES=("SUPER + D" "SUPER + ALT + D" "SUPER + CTRL + ALT + P")

die() { echo "install-shortcuts: $*" >&2; exit 1; }
say() { echo "  $*"; }

# A path may be a symlink into a dotfiles repo -- editing in place through the
# link would replace the link with a regular file and quietly detach the repo.
real_path() {
  local p=$1
  [[ -e $p ]] && readlink -f -- "$p" || echo "$p"
}

backup() {
  local f=$1
  [[ -f $f ]] || return 0
  cp -- "$f" "$f.bak.$(date +%s)"
}

# ---------------------------------------------------------------- conflicts

# SHIFT=1 CAPS=2 CTRL=4 ALT=8 MOD2=16 MOD3=32 SUPER=64 MOD5=128
modmask_of() {
  local m=0 tok
  for tok in $(tr 'a-z+' 'A-Z ' <<<"$1"); do
    case "$tok" in
      SUPER|MOD4|WIN|LOGO) m=$((m | 64)) ;;
      SHIFT)               m=$((m | 1))  ;;
      CTRL|CONTROL)        m=$((m | 4))  ;;
      ALT|MOD1)            m=$((m | 8))  ;;
      CAPS)                m=$((m | 2))  ;;
    esac
  done
  echo "$m"
}

# Asks the compositor, not the config file. Bindings can come from a symlinked
# Lua config that generates them at runtime, in which case there is no text to
# grep and `hyprctl binds` is the only thing that knows.
occupant() {
  local mask key
  mask=$(modmask_of "$1")
  key=$(tr 'a-z' 'A-Z' <<<"${1##*+}" | tr -d ' ')
  hyprctl binds -j | jq -r --argjson m "$mask" --arg k "$key" '
    [ .[] | select(.modmask == $m and (.key | ascii_upcase) == $k) ]
    | if length == 0 then "FREE" else (map(.description // .dispatcher) | join("; ")) end'
}

choose_combo() {
  local combo who
  for combo in "${CANDIDATES[@]}"; do
    who=$(occupant "$combo")
    if [[ $who == FREE ]]; then echo "$combo"; return 0; fi
    say "$combo is taken by: $who" >&2
  done
  return 1
}

# ------------------------------------------------------------- the keybinding

strip_block() {  # file begin end
  [[ -f $1 ]] || return 0
  sed -i "\|$2|,\|$3|d" -- "$1"
}

# hyprctl says which keys are occupied but not what they run: a Lua config
# reports every binding as dispatcher "__lua". So "is one of these already
# ours" can only be answered from the text, and a miss here costs a redundant
# second key rather than anything broken.
existing_binding() {
  grep -n -- "$PLUGIN_ID" "$1" 2>/dev/null | grep -v ':[[:space:]]*--' | head -1
}

install_binding() {
  local file combo found
  file=$(real_path "$BINDINGS")
  [[ -f $file ]] || die "no bindings file at $file"

  found=$(existing_binding "$file")
  if [[ -n $found ]]; then
    say "a key for this plugin is already set up at $file:${found%%:*}"
    say "leaving it alone -- delete that line and re-run to have it managed here"
    return 0
  fi

  if ! combo=$(choose_combo); then
    cat >&2 <<MSG

  Every candidate key is already taken, and taking one from you is not this
  script's decision to make. Pick a free one and add it yourself:

    o.bind("<your key>", "Displays", "$ACTION")

MSG
    return 1
  fi

  backup "$file"
  strip_block "$file" "$BEGIN" "$END"
  cat >>"$file" <<LUA
$BEGIN
o.bind("$combo", "Displays", "$ACTION")
$END
LUA
  say "bound $combo -> Displays  ($file)"
}

# ---------------------------------------------------------------- the menu row

install_menu() {
  local file tmp had_entry
  file=$(real_path "$MENU")
  mkdir -p -- "${file%/*}"
  [[ -f $file ]] || printf '{\n}\n' >"$file"

  backup "$file"
  strip_block "$file" "$JBEGIN" "$JEND"

  # A hand-added row under the same id would become a duplicate JSON key --
  # legal, silently last-one-wins, and baffling to debug.
  if grep -qE '^[[:space:]]*"displays"[[:space:]]*:' -- "$file"; then
    say "a \"displays\" row already exists in $file -- leaving it alone"
    return 0
  fi

  # A trailing comma is only safe when a key follows ours. Ours goes in right
  # after the opening brace, so "a key follows" means the file already has one.
  had_entry=$(grep -cE '^[[:space:]]*"' -- "$file" || true)

  tmp=$file.displaywright.new
  awk -v begin="$JBEGIN" -v end="$JEND" -v comma="$([[ $had_entry -gt 0 ]] && echo , || echo '')" '
    BEGIN { done = 0 }
    {
      print
      if (!done && $0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
        print "  " begin
        print "  \"displays\": {"
        print "    \"icon\": \"\xf3\xb0\x8d\xb9\","
        print "    \"label\": \"Displays\","
        print "    \"description\": \"Arrange your monitors, resolution, scale and rotation\","
        print "    \"aliases\": [\"display\", \"monitor\", \"monitors\", \"screen\", \"arrange\", \"wallpaper\"],"
        print "    \"action\": \"omarchy-shell shell toggle ai.bkblab.displaywright \x27{}\x27\""
        print "  }" comma
        print "  " end
        done = 1
      }
    }
  ' "$file" >"$tmp"

  # Comment-only lines are the only comments the shipped template uses, so
  # dropping them is enough to hand the rest to jq for a syntax check.
  if ! sed 's|^[[:space:]]*//.*$||' "$tmp" | jq empty 2>/dev/null; then
    rm -f -- "$tmp"
    die "refusing to write $file: the result would not parse"
  fi
  mv -f -- "$tmp" "$file"
  say "added a Displays row to the Omarchy menu  ($file)"
}

# -------------------------------------------------------------------- reload

reload_hyprland() {
  # Pointed somewhere else by the test harness: nothing the compositor reads
  # was touched, so there is nothing for it to reload.
  [[ -n ${HYPR_BINDINGS:-} ]] && return 0
  hyprctl reload >/dev/null 2>&1 || true
  local errs
  errs=$(hyprctl configerrors 2>/dev/null | grep -v '^no errors' || true)
  if [[ -n $errs ]]; then
    echo "$errs" >&2
    die "Hyprland reported config errors -- a .bak file next to each edited file has the previous contents"
  fi
}

# ---------------------------------------------------------------------- main

if [[ ${1:-} == --remove ]]; then
  f=$(real_path "$BINDINGS"); backup "$f"; strip_block "$f" "$BEGIN" "$END"
  say "removed the keybinding  ($f)"
  f=$(real_path "$MENU");     backup "$f"; strip_block "$f" "$JBEGIN" "$JEND"
  say "removed the menu row  ($f)"
  reload_hyprland
  exit 0
fi

command -v jq >/dev/null || die "jq is required"
command -v hyprctl >/dev/null || die "hyprctl is required"

echo "Displaywright shortcuts:"
install_menu
install_binding || true
reload_hyprland
echo
echo "  Open it from the Omarchy menu (SUPER + SPACE, type 'Displays'),"
echo "  from the Apps menu (SUPER + ALT + SPACE), or with the key above."
