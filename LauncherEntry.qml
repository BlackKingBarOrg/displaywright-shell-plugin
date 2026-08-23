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

  readonly property string appsDir:
    Quickshell.env("HOME") + "/.local/share/applications"
  readonly property string marker: "^X-Displaywright-Managed=true$"

  //: Run through setsid. "Detached" only means Quickshell stops waiting on
  //: it: the child stays in the shell's process group, and omarchy-shell tears
  //: its plugin services down over and over while installing, which takes the
  //: group with it. That is why a toast never arrived, why a script that slept
  //: never came back, and why this loop wrote its first file and died before
  //: the second. Its own session survives.
  readonly property string installScript:
      'dir=$1; apps=$2; mark=$3\n'
    + 'mkdir -p "$apps" || exit 0\n'
    + 'for n in displaywright displaywright-shortcuts; do\n'
    + '  src=$dir/$n.desktop; dst=$apps/$n.desktop\n'
    + '  [ -f "$src" ] || continue\n'
    + '  if [ -e "$dst" ] && ! grep -q "$mark" "$dst"; then continue; fi\n'
    + '  tmp=$dst.displaywright.new\n'
    + '  sed -e "s|@ICON@|$dir/icon.png|" -e "s|@SCRIPT@|$dir/install-shortcuts.sh|" "$src" > "$tmp" || continue\n'
    + '  if cmp -s "$tmp" "$dst"; then rm -f "$tmp"; else mv -f "$tmp" "$dst"; fi\n'
    + 'done\n'

  //: A destruction is almost never an uninstall: the shell tears every plugin
  //: service down and rebuilds it on each reload, and `omarchy plugin add`
  //: fires dozens of those while installing. Deleting here on every teardown
  //: removed the entry the next instance had just written, which is why a
  //: fresh install ended with nothing in the launcher. The plugin folder is
  //: the discriminator -- still there means a reload.
  readonly property string removeScript:
      'dir=$3; apps=$1; mark=$2\n'
    + '[ -d "$dir" ] && exit 0\n'
    + 'for n in displaywright displaywright-shortcuts; do\n'
    + '  f=$apps/$n.desktop\n'
    + '  grep -q "$mark" "$f" 2>/dev/null && rm -f "$f"\n'
    + 'done\n'

  property bool installed: false
  property string sourceDir: ""

  // The shell assigns manifest after createObject() has already run
  // Component.onCompleted, so the paths are built when it arrives rather than
  // bound -- a binding has not re-evaluated by the time that fires.
  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    root.sourceDir = dir
    //: execDetached reports nothing back, so this line is the only evidence
    //: that the entry was attempted. It has been needed twice.
    console.log("displaywright: installing launcher entries in " + root.appsDir)
    Quickshell.execDetached(["setsid", "sh", "-c", installScript, "sh",
                             dir, root.appsDir, marker])
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["setsid", "sh", "-c", removeScript, "sh", root.appsDir,
                             marker, root.sourceDir])
  }
}
