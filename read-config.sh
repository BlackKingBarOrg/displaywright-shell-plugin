#!/bin/bash
#
# Reads one of this plugin's config files, bounded.
#
# Quickshell's FileView has no size limit, no way to refuse a special file, and
# no no-follow: it reads whatever the path resolves to straight into the shell's
# own process. A wallpapers.json of a few gigabytes, or one symlinked at
# /dev/zero, therefore takes the whole desktop down rather than this plugin --
# and Arrange.qml read one of them with blockLoading, on the main thread.
#
# A symlinked config is legitimate (people keep these in dotfiles repos), so the
# test is not "is it a link" but "does it resolve to a regular file of a sane
# size". `[ -f ]` follows the link and is false for a device or a fifo, which is
# the hazard; the cap covers the rest. Everything real here is a few hundred
# bytes, so the limit is three orders of magnitude clear of any honest file.

set -uo pipefail

path=${1:?usage: read-config.sh <path> [max-bytes]}
max=${2:-262144}

[ -f "$path" ] || exit 0
size=$(stat -Lc %s -- "$path" 2>/dev/null) || exit 0

if [ "$size" -gt "$max" ]; then
  printf 'displaywright: %s is %s bytes, past the %s byte limit -- ignoring it\n' \
    "$path" "$size" "$max" >&2
  exit 0
fi

# Bounded a second time at the read itself, so a file that grows between the
# stat and the read still cannot hand back more than the cap.
head -c "$max" -- "$path"
