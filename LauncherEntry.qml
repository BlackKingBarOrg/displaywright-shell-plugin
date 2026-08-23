// Installs the launcher entry, so the overlay is reachable from the app
// launcher and SUPER+SPACE search without the user wiring up a keybind first.
//
// Omarchy has no install hook and no manifest field for registering one: a
// plugin is a git clone into ~/.config/omarchy/plugins and nothing more. A
// plugin that only tells you to bind a key yourself reads, to everyone who
// installs it, as a plugin that does not work -- there is nothing to click and
// nothing to find by name.
//
// Only a file carrying the X-Displaywright-Managed marker is ever written or
// deleted, so an entry the user wrote by hand is left alone.

import QtQuick
import Quickshell

QtObject {
  id: root

  property var manifest: null

  readonly property string dest:
    Quickshell.env("HOME") + "/.local/share/applications/displaywright.desktop"
  readonly property string marker: "^X-Displaywright-Managed=true$"

  readonly property string installScript:
      '[ -f "$1" ] || exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'mkdir -p "${2%/*}" || exit 0\n'
    + 'tmp=$2.displaywright.new\n'
    + 'sed "s|@ICON@|$4|" "$1" > "$tmp" || exit 0\n'
    + 'if cmp -s "$tmp" "$2"; then rm -f "$tmp"; else mv -f "$tmp" "$2"; fi\n'

  readonly property string removeScript:
    'grep -q "$2" "$1" 2>/dev/null && rm -f "$1"\n'

  property bool installed: false

  // The shell assigns manifest after createObject() has already run
  // Component.onCompleted, so the paths are built when it arrives rather than
  // bound -- a binding has not re-evaluated by the time that fires.
  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    //: execDetached reports nothing back, so this line is the only evidence
    //: that the entry was attempted. It has been needed twice.
    console.log("displaywright: installing launcher entry at " + dest)
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             dir + "/displaywright.desktop", dest, marker,
                             dir + "/icon.png"])
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", dest, marker])
  }
}
