// Colours for the arrangement overlay.
//
// A plugin overlay is mounted through the shell's Loader, and a component
// loaded that way cannot resolve `qs.Commons` -- Color comes back undefined and
// every colour binding warns. The service can import it, so the live theme
// arrives through `service.palette`; these literals are what the overlay draws
// with until it does, and if it never does.

import QtQuick

QtObject {
  //: Live values from the shell theme, when the service has handed them over.
  property var theme: null

  function pick(name, fallback) {
    return theme && theme[name] !== undefined ? theme[name] : fallback
  }

  readonly property color background: pick("background", "#16161d")
  readonly property color text: pick("text", "#e6e6ea")
  readonly property color muted: pick("muted", "#9a9aa6")
  readonly property color placeholder: pick("placeholder", "#6f6f7b")
  readonly property color border: pick("border", "#33333f")
  readonly property color active: pick("active", "#242430")
  readonly property color accent: pick("accent", "#3584e4")
  readonly property color scrim: pick("scrim", "#cc0c0c11")
  readonly property color selectedBackground: pick("selectedBackground", "#25324a")
  readonly property color selectedBorder: pick("selectedBorder", "#6aa3f0")
  readonly property color selectedText: pick("selectedText", "#ffffff")
  readonly property color unselectedBorder: pick("unselectedBorder", "#41414f")
  readonly property color textError: pick("textError", "#f08a8a")
  readonly property color countdown: pick("countdown", "#e8b04b")
}
