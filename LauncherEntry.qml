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

  //: Shown once, ever. Someone who has just installed a plugin has no reason
  //: to guess that a keybinding needs a separate command -- still less that a
  //: plugin is not permitted to register one for itself. Clicking the toast
  //: runs the installer in a terminal, so the long path never has to be typed.
  readonly property string welcomeScript:
      'state=${XDG_STATE_HOME:-$HOME/.local/state}/displaywright\n'
    + '[ -e "$state/welcomed" ] && exit 0\n'
    + 'mkdir -p "$state" || exit 0\n'
    + ': > "$state/welcomed"\n'
    + 'command -v omarchy-notification-send >/dev/null || exit 0\n'
    + 'omarchy-notification-send -u normal -g "󰍹" \\\n'
    + '  --exec "omarchy-launch-floating-terminal-with-presentation $1" \\\n'
    + '  "Displaywright is ready" \\\n'
    + '  "Open it with SUPER + ALT + SPACE, then type Displays. Click this to add a keyboard shortcut and an Omarchy menu row."\n'

  //: The shell destroys and recreates every plugin service on each reload,
  //: and `omarchy plugin add` fires dozens of reloads while it installs. A
  //: destruction is therefore almost never an uninstall -- and because these
  //: run detached and unordered, a remove that fires on a reload deletes the
  //: entry the next instance just wrote. That is why the entry was missing
  //: after a fresh install, every time.
  //:
  //: The plugin folder is the discriminator: still there means a reload, gone
  //: means the plugin really went. The wait lets the removal finish first --
  //: omarchy-plugin-remove disables the plugin before it moves the folder.
  readonly property string removeScript:
      'sleep 3\n'
    + '[ -d "$3" ] && exit 0\n'
    + 'grep -q "$2" "$1" 2>/dev/null && rm -f "$1"\n'

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
    console.log("displaywright: installing launcher entry at " + dest)
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             dir + "/displaywright.desktop", dest, marker,
                             dir + "/icon.png"])
    //: Sent with no delay of any kind. A QML Timer never fired here, and a
    //: `sleep` inside the detached script never came back either -- both work
    //: under a bare Quickshell, and neither survives the teardown storm that
    //: omarchy-shell puts a plugin through while it installs. Anything that
    //: waits gets collected; only work done immediately lands.
    Quickshell.execDetached(["sh", "-c", welcomeScript, "sh",
                             dir + "/install-shortcuts.sh"])
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", dest, marker,
                             root.sourceDir])
  }
}
