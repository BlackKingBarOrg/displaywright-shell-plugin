#!/usr/bin/env bash
#
# Adds the three things a plugin cannot reliably add for itself: the launcher
# entry, a row in the Omarchy menu, and a keybinding.
#
# Omarchy's manifest has no field for any of them, and `omarchy plugin add` runs
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

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DESKTOP_DIR="${DW_DESKTOP_DIR:-$HOME/.local/share/applications}"
DESKTOP_SRC="$PLUGIN_DIR/displaywright.desktop"
DESKTOP_DEST="$DESKTOP_DIR/displaywright.desktop"
DESKTOP_MARKER="X-Displaywright-Managed=true"

BEGIN="-- >>> displaywright (managed) >>>"
END="-- <<< displaywright <<<"
JBEGIN="// >>> displaywright (managed) >>>"
JEND="// <<< displaywright <<<"

# Tried in order. The first one nothing else has wins.
CANDIDATES=("SUPER + D" "SUPER + ALT + D" "SUPER + CTRL + ALT + P")
CHOSEN_COMBO=""

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

# ----------------------------------------------------------- the launcher entry

# LauncherEntry.qml writes this file too, and on a fresh install that is enough.
# It is not enough on an update: the shell compiled Wallpaper.qml before this
# version's files existed and goes on running what it compiled, so a plugin that
# has only just gained a file cannot execute it. Bash has no such cache. Both
# writers use the same marker and both leave a byte-identical file untouched, so
# whichever gets there first, the other is a no-op.
install_desktop() {
  local tmp
  [[ -f $DESKTOP_SRC ]] || { say "no displaywright.desktop beside this script -- skipped"; return 1; }
  if [[ -e $DESKTOP_DEST ]] && ! grep -q "$DESKTOP_MARKER" "$DESKTOP_DEST"; then
    say "$DESKTOP_DEST is not ours -- left alone"
    return 1
  fi
  mkdir -p -- "$DESKTOP_DIR"
  tmp=$DESKTOP_DEST.displaywright.new
  sed "s|@ICON@|$PLUGIN_DIR/icon.png|" "$DESKTOP_SRC" >"$tmp"
  if cmp -s "$tmp" "$DESKTOP_DEST"; then rm -f -- "$tmp"; else mv -f -- "$tmp" "$DESKTOP_DEST"; fi
  say "launcher entry in place  ($DESKTOP_DEST)"
}

remove_desktop() {
  [[ -f $DESKTOP_DEST ]] || return 0
  if ! grep -q "$DESKTOP_MARKER" "$DESKTOP_DEST"; then
    say "$DESKTOP_DEST is not ours -- left alone"
    return 0
  fi
  rm -f -- "$DESKTOP_DEST"
  say "removed the launcher entry  ($DESKTOP_DEST)"
}

# ------------------------------------------------------------- the keybinding

# Returns 0 having cut the block or having found nothing of ours to cut, and 1
# having refused. A block is only ever cut with both of its markers present: on
# the opening one alone `sed '/begin/,/end/d'` runs to the end of the file and
# takes everything after it with it, which for a bindings file someone keeps in
# a dotfiles repo is the whole rest of their keyboard.
strip_block() {  # file begin end
  local file=$1 begin=$2 end=$3
  [[ -f $file ]] || return 0
  grep -qF -- "$begin" "$file" || return 0
  if ! grep -qF -- "$end" "$file"; then
    cat >&2 <<MSG

  $file carries our opening marker and no closing one, so there is no end to
  cut to and nothing was changed. Delete this line by hand, then run this
  again:

    $begin

MSG
    return 1
  fi
  sed -i "\|$begin|,\|$end|d" -- "$file"
}

install_binding() {
  local file combo rc=0
  file=$(real_path "$BINDINGS")
  [[ -f $file ]] || die "no bindings file at $file"

  if ! combo=$(choose_combo); then
    cat >&2 <<MSG

  Every candidate key is already taken, and taking one from you is not this
  script's decision to make. Pick a free one and add it yourself:

    o.bind("<your key>", "Displays", "$ACTION")

MSG
    return 1
  fi

  backup "$file"
  strip_block "$file" "$BEGIN" "$END" || rc=$?
  (( rc == 0 )) || return 1
  cat >>"$file" <<LUA
$BEGIN
o.bind("$combo", "Displays", "$ACTION")
$END
LUA
  CHOSEN_COMBO=$combo
  say "bound $combo -> Displays  ($file)"
}

# ---------------------------------------------------------------- the menu row

install_menu() {
  local file tmp had_entry status=0 rc=0
  file=$(real_path "$MENU")
  mkdir -p -- "${file%/*}"
  [[ -f $file ]] || printf '{\n}\n' >"$file"

  backup "$file"
  strip_block "$file" "$JBEGIN" "$JEND" || rc=$?
  (( rc == 0 )) || return 1

  # A trailing comma is only safe when a key follows ours. Ours goes in right
  # after the opening brace, so "a key follows" means the file already has one.
  had_entry=$(grep -cE '^[[:space:]]*"' -- "$file" || true)

  tmp=$file.displaywright.new
  awk -v begin="$JBEGIN" -v end="$JEND" -v comma="$([[ $had_entry -gt 0 ]] && echo , || echo '')" '
    BEGIN { placed = 0 }
    {
      print
      if (!placed && $0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
        print "  " begin
        print "  \"displays\": {"
        print "    \"icon\": \"\xf3\xb0\x8d\xb9\","
        print "    \"label\": \"Displays\","
        print "    \"description\": \"Arrange your monitors, resolution, scale and rotation\","
        print "    \"aliases\": [\"display\", \"monitor\", \"monitors\", \"screen\", \"arrange\", \"wallpaper\"],"
        print "    \"action\": \"omarchy-shell shell toggle ai.bkblab.displaywright \x27{}\x27\""
        print "  }" comma
        print "  " end
        placed = 1
      }
    }
    END { if (!placed) exit 3 }
  ' "$file" >"$tmp" || status=$?

  # The row goes in after the line that is nothing but the outermost brace. A
  # file that opens `{ "a": 1 }` has no such line, and awk used to print
  # nothing while this function claimed the row was added.
  if (( status == 3 )); then
    rm -f -- "$tmp"
    cat >&2 <<MSG

  Found nowhere to put the row in $file: no line in it is just an opening
  brace. Nothing was changed. Paste this inside the outermost { } to get the
  row by hand:

    "displays": {
      "icon": "󰍹", "label": "Displays",
      "action": "$ACTION"
    }

MSG
    return 1
  fi
  (( status == 0 )) || { rm -f -- "$tmp"; die "awk failed reading $file"; }

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

# An update leaves the shell running the QML it compiled before the update: the
# renderer and the overlay on disk are not the ones in memory until it restarts.
# A fresh install never needs this and an update cannot do without it, and since
# telling the two apart is guesswork, it restarts either way -- a second of bar.
restart_shell() {
  # Under the test harness nothing the shell reads was touched.
  [[ -n ${HYPR_BINDINGS:-}${OMARCHY_MENU_EXT:-}${DW_DESKTOP_DIR:-} ]] && return 0
  command -v omarchy >/dev/null 2>&1 || return 0
  say "restarting omarchy-shell, so the version on disk is the one running"
  omarchy restart shell >/dev/null 2>&1 || true
}

remove_block_from() {  # path begin end what
  local f
  f=$(real_path "$1")
  [[ -f $f ]] || return 0
  grep -qF -- "$2" "$f" || { say "no $4 of ours in $f"; return 0; }
  backup "$f"
  if strip_block "$f" "$2" "$3"; then say "removed $4  ($f)"; fi
}

# ---------------------------------------------------------------------- main

if [[ ${1:-} == --remove ]]; then
  echo "Displaywright shortcuts, removing:"
  remove_desktop
  remove_block_from "$MENU" "$JBEGIN" "$JEND" "menu row"
  remove_block_from "$BINDINGS" "$BEGIN" "$END" "keybinding"
  reload_hyprland
  exit 0
fi

command -v jq >/dev/null || die "jq is required"
command -v hyprctl >/dev/null || die "hyprctl is required"

echo "Displaywright shortcuts:"
desktop_ok=0; menu_ok=0; binding_ok=0
install_desktop && desktop_ok=1 || true
install_menu    && menu_ok=1    || true
install_binding && binding_ok=1 || true
reload_hyprland

# Only what actually landed. Claiming a way in that was never installed is how
# this reads as broken to whoever tries the one line that does not work.
echo
if (( desktop_ok + menu_ok + binding_ok == 0 )); then
  echo "  Nothing was installed -- see the messages above."
  exit 1
fi

echo "  Open it from:"
if (( desktop_ok )); then echo "    the Apps menu (SUPER + ALT + SPACE), type 'Displays'"; fi
if (( menu_ok ));    then echo "    the Omarchy menu (SUPER + SPACE), type 'Displays'"; fi
if (( binding_ok )); then echo "    $CHOSEN_COMBO"; fi

# Last, and only having changed something: a restart costs a second of bar,
# which is a fair price for finishing an update and no price at all worth
# paying for a run that installed nothing.
restart_shell
