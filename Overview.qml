import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "workspace-label.js" as Labels

// NittyGriddy overlay for Omarchy Quattro.
// The shell calls open(payloadJson) on summon and close() on hide.
// keepLoaded keeps this item mounted, so socket2 custom events and the
// timsonner.nitty-griddy IPC target are live before the first swipe.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "timsonner.nitty-griddy"
  readonly property string pluginDir: {
    var dir = (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
    if (!dir)
      dir = Quickshell.env("HOME") + "/.config/omarchy/plugins/timsonner.nitty-griddy"
    while (dir.length > 1 && dir.charAt(dir.length - 1) === "/")
      dir = dir.slice(0, dir.length - 1)
    return dir
  }

  property bool opened: false
  property bool surfaceShown: false
  property bool hiding: false
  property real reveal: 0.96
  property string filterText: ""
  // Empty means every workspace. Otherwise the Hyprland workspace id.
  // The strip shows All, then this monitor's numbers. 1 through 9 stay even
  // when empty. Slot 10 is added when that workspace exists. The label is the
  // slot on this monitor, so Hyprland id 14 reads as workspace 4.
  property string workspacePage: ""
  property var pageNames: []
  readonly property int workspaceSlots: 10
  property var monitorBlocks: ({})
  property string phase: "ready"
  property string errorText: ""
  property var allWindows: []
  property var windows: []
  property var waylandByAddress: ({})
  property string selectedAddress: ""
  property int selectedIndex: -1
  property bool selectionPinned: false
  // Normal-workspace window that was focused before this open. Restored on an
  // empty dismiss. A special: client is not stashed here.
  property string priorAddress: ""
  // Bumps on every arm and disarm so a slow arm cannot turn no_warps back on.
  property int warpGen: 0
  // Bumps on every special-workspace arm and settle. The helper file is what
  // dismiss restores; these mirror its stdout for this open.
  property int specialGen: 0
  property bool priorWasSpecial: false
  property bool specialsSettled: false
  property var specialAddresses: []
  property var hiddenSpecials: []
  property bool opening: false
  property bool restoreOnBlur: false
  property bool blurAgain: false
  property int blurToken: 0
  // Two layers so a workspace change can fade one blurred picture into the
  // next. The grid itself stays put. All, and a workstation with no windows,
  // leave both layers clear so the blurred wallpaper shows. A workstation
  // with windows shows those windows, and opening or closing one updates it.
  property var backdropFront: []
  property var backdropBack: []
  property bool backdropShowFront: true
  property bool backdropWindows: false
  property bool backdropReady: false
  property bool backdropInstant: false
  property string backdropShownKey: ""
  property string wallpaperPath: ""
  property int wallpaperGen: 0
  property bool wallpaperAgain: false
  property bool posterAgain: false
  property string posterPending: ""
  property int posterToken: 0
  readonly property string wallpaperStateHome: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
  readonly property string wallpaperLink: wallpaperStateHome + "/omarchy/current/background"
  readonly property string themeBackgrounds: wallpaperStateHome + "/omarchy/current/theme/backgrounds"
  // Pressed card, copied at press time so a hover or a refresh cannot retarget the click.
  property bool pointerHold: false
  property int heldIndex: -1
  property string heldAddress: ""
  // Survives endPointerHold so a release-before-click still activates this card.
  property string pressedAddress: ""
  property bool deferredRefresh: false
  property real hoverIgnoreUntil: 0
  // False while the grid is rebuilding. Flickable must not see that press.
  property bool scrollerInteractive: false
  property int thumbGeneration: 0
  property bool swallowEsc: false
  property var pendingClients: []
  property bool clientSnapshotRejected: false

  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property color accent: Commons.Color.accent
  readonly property color selectedFill: Commons.Color.menu.selectedBackground
  readonly property int radius: Style.cornerRadius
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.space(14)
  readonly property string uiFont: Style.font.menuFamily
  readonly property real viewWidth: Math.max(1, panel.width - pad * 2)
  readonly property real viewHeight: Math.max(1, panel.height - pad * 2 - Style.space(96) - Style.space(34))
  readonly property int columns: {
    var n = Math.max(1, windows.length)
    var aspect = viewWidth / Math.max(1, viewHeight)
    var cols = Math.round(Math.sqrt(n * Math.max(0.5, aspect)))
    if (cols < 1)
      cols = 1
    if (cols > n)
      cols = n
    return cols
  }
  readonly property real cardWidth: {
    var inner = Math.max(1, viewWidth - gap * (columns - 1))
    return Math.max(Style.space(140), Math.min(Style.space(460), inner / columns))
  }
  readonly property real cardHeight: Math.max(Style.space(156), Math.min(Style.space(300), cardWidth * 0.72))

  Behavior on reveal {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  function open(payloadJson) {
    if (root.opened) {
      root.presentGrid()
      return
    }
    if (root.opening)
      return
    // Stash and blur before the overlay is interactive. An exclusive layer
    // cannot clear the focused client once it is mapped. no_focus does not
    // drop that client, and a client on special:qconsole keeps the seat until
    // that workspace is hidden. Arm no_warps, blur every mapped special
    // client, and toggle shown specials off before the layer is interactive.
    root.opening = true
    root.restoreOnBlur = false
    root.specialsSettled = false
    root.priorWasSpecial = false
    root.specialAddresses = []
    root.hiddenSpecials = []
    var focused = root.focusedClientInfo()
    if (root.specialSuffix(focused.workspace)) {
      root.priorAddress = ""
      root.priorWasSpecial = true
    } else {
      root.priorAddress = focused.address
    }
    root.armNoWarps()
    root.launchBlur()
  }

  function presentGrid() {
    root.armNoWarps()
    root.opening = false
    blurWait.stop()
    root.opened = true
    root.surfaceShown = true
    // A previous summon can leave a hold, a deferred rebuild, or a scroll
    // offset. The next press then misses the card and only dismisses.
    root.pointerHold = false
    root.heldIndex = -1
    root.heldAddress = ""
    root.pressedAddress = ""
    root.deferredRefresh = false
    root.backdropReady = false
    root.backdropShownKey = ""
    root.backdropFront = []
    root.backdropBack = []
    root.backdropShowFront = true
    root.backdropWindows = false
    root.resolveWallpaper()
    root.hoverIgnoreUntil = 0
    root.hiding = false
    root.scrollerInteractive = false
    root.filterText = ""
    root.workspacePage = ""
    root.selectedAddress = ""
    root.selectedIndex = -1
    root.selectionPinned = false
    root.errorText = ""
    root.phase = "loading"
    root.reveal = 0.96
    Qt.callLater(function() {
      if (!root.opened)
        return
      scroller.contentX = 0
      scroller.contentY = 0
    })
    try { Hyprland.refreshToplevels() } catch (e) {}
    root.refresh()
    root.reclaimFocus()
    backdropTimer.tries = 0
    backdropTimer.start()
    root.playReveal()
  }

  function launchBlur() {
    // One blur at a time. A summon that arrives while hyprctl is still
    // running waits for that process to exit, then starts the new one.
    if (blurCapture.running) {
      root.blurAgain = true
      root.blurToken = root.blurToken + 1
      blurCapture.token = -1
      return
    }
    root.blurAgain = false
    root.restoreOnBlur = false
    root.blurToken = root.blurToken + 1
    blurCapture.token = root.blurToken
    blurWait.restart()
    root.specialGen = root.specialGen + 1
    var gen = String(root.specialGen)
    if (root.priorAddress)
      blurCapture.command = [root.helper("blur-focus"), "--grid-open", "--gen", gen, root.priorAddress]
    else
      blurCapture.command = [root.helper("blur-focus"), "--grid-open", "--gen", gen]
    blurCapture.running = true
  }

  function finishBlur() {
    if (!root.opening || root.hiding)
      return
    root.presentGrid()
  }

  function toplevelWorkspaceName(item) {
    if (!item)
      return ""
    var ws = ""
    try {
      ws = root.workspaceName(item.workspace)
    } catch (e) {
      ws = ""
    }
    if (ws)
      return ws
    var ipc = null
    try { ipc = item.lastIpcObject || null } catch (e2) { ipc = null }
    if (ipc && ipc.workspace)
      return String(ipc.workspace.name || "")
    return ""
  }

  // The client Hyprland still considers focused, plus its workspace name.
  // blur-focus reads `hyprctl activewindow -j` when the address is empty.
  function focusedClientInfo() {
    var info = { address: "", workspace: "" }
    var i
    try {
      if (Hyprland.activeToplevel) {
        info.address = root.hexAddress(Hyprland.activeToplevel.address)
        info.workspace = root.toplevelWorkspaceName(Hyprland.activeToplevel)
      }
    } catch (e) {
      info.address = ""
      info.workspace = ""
    }
    if (info.address)
      return info
    var hypr = []
    try {
      if (Hyprland.toplevels && Hyprland.toplevels.values)
        hypr = Hyprland.toplevels.values
    } catch (e2) {
      hypr = []
    }
    for (i = 0; i < hypr.length; i++) {
      var item = hypr[i]
      if (!item || !item.activated)
        continue
      info.address = root.hexAddress(item.address)
      if (!info.address)
        continue
      info.workspace = root.toplevelWorkspaceName(item)
      return info
    }
    var tops = []
    try {
      if (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
        tops = ToplevelManager.toplevels.values
    } catch (e3) {
      tops = []
    }
    for (i = 0; i < tops.length; i++) {
      var top = tops[i]
      if (!top)
        continue
      var attached = top.HyprlandToplevel || null
      var activated = !!top.activated
      if (attached && attached.activated !== undefined)
        activated = !!attached.activated
      if (!activated)
        continue
      info.address = root.hexAddress(attached ? attached.address : "")
      if (!info.address)
        continue
      info.workspace = root.toplevelWorkspaceName(attached)
      if (!info.workspace)
        info.workspace = root.toplevelWorkspaceName(top)
      return info
    }
    return info
  }

  function specialSuffix(workspace) {
    var name = String(workspace || "")
    if (name.indexOf("special:") !== 0)
      return ""
    var suffix = name.slice("special:".length)
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(suffix))
      return ""
    return suffix
  }

  function specialSuffixForAddress(address) {
    var i
    var rows = root.windows || []
    for (i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].address === address)
        return root.specialSuffix(rows[i].workspace)
    }
    rows = root.allWindows || []
    for (i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].address === address)
        return root.specialSuffix(rows[i].workspace)
    }
    return ""
  }

  function rememberSpecial(addr) {
    var next = root.specialAddresses.slice()
    var i
    for (i = 0; i < next.length; i++) {
      if (next[i] === addr)
        return
    }
    next.push(addr)
    root.specialAddresses = next
  }

  function rememberHidden(name) {
    var next = root.hiddenSpecials.slice()
    var i
    for (i = 0; i < next.length; i++) {
      if (next[i] === name)
        return
    }
    next.push(name)
    root.hiddenSpecials = next
  }

  // Restore or drop the specials this open hid. The helper unsets no_focus
  // on the clients it blurred so a quake window is not left unable to focus.
  function settleSpecials(action, extra) {
    if (root.specialsSettled)
      return
    root.specialsSettled = true
    root.specialGen = root.specialGen + 1
    var gen = String(root.specialGen)
    if (action === "dismiss") {
      Quickshell.execDetached([
        root.helper("blur-focus"),
        "--grid-dismiss",
        "--gen",
        gen
      ])
      return
    }
    if (action === "activate") {
      var clean = root.hexAddress(extra)
      if (!clean)
        return
      var suffix = root.specialSuffixForAddress(clean)
      if (suffix)
        Quickshell.execDetached([
          root.helper("blur-focus"),
          "--grid-activate",
          "--gen",
          gen,
          clean,
          suffix
        ])
      else
        Quickshell.execDetached([
          root.helper("blur-focus"),
          "--grid-activate",
          "--gen",
          gen,
          clean
        ])
    }
  }

  // The client Hyprland still considers focused. Prefer the in-process
  // toplevel list; blur-focus reads `hyprctl activewindow -j` when this is empty.
  function focusedAddress() {
    var addr = ""
    var i
    try {
      if (Hyprland.activeToplevel)
        addr = root.hexAddress(Hyprland.activeToplevel.address)
    } catch (e) {
      addr = ""
    }
    if (addr)
      return addr
    var hypr = []
    try {
      if (Hyprland.toplevels && Hyprland.toplevels.values)
        hypr = Hyprland.toplevels.values
    } catch (e2) {
      hypr = []
    }
    for (i = 0; i < hypr.length; i++) {
      var item = hypr[i]
      if (!item || !item.activated)
        continue
      addr = root.hexAddress(item.address)
      if (addr)
        return addr
    }
    var tops = []
    try {
      if (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
        tops = ToplevelManager.toplevels.values
    } catch (e3) {
      tops = []
    }
    for (i = 0; i < tops.length; i++) {
      var top = tops[i]
      if (!top)
        continue
      var attached = top.HyprlandToplevel || null
      var activated = !!top.activated
      if (attached && attached.activated !== undefined)
        activated = !!attached.activated
      if (!activated)
        continue
      addr = root.hexAddress(attached ? attached.address : "")
      if (addr)
        return addr
    }
    return ""
  }

  function clientStillMapped(address) {
    if (!address)
      return false
    var i
    if (root.allWindows && root.allWindows.length) {
      for (i = 0; i < root.allWindows.length; i++) {
        if (root.allWindows[i].address === address)
          return true
      }
      return false
    }
    var hypr = []
    try {
      if (Hyprland.toplevels && Hyprland.toplevels.values)
        hypr = Hyprland.toplevels.values
    } catch (e) {
      hypr = []
    }
    if (!hypr.length)
      return true
    for (i = 0; i < hypr.length; i++) {
      if (hypr[i] && root.hexAddress(hypr[i].address) === address)
        return true
    }
    return false
  }

  function scheduleRestore(address) {
    if (!address || !root.clientStillMapped(address))
      return
    Quickshell.execDetached([root.helper("focus-window"), address])
  }

  function noteBlurAddress(line) {
    var text = String(line || "").replace(/\r/g, "").trim()
    if (text === "prior-special") {
      if (blurCapture.token !== root.blurToken)
        return
      root.priorWasSpecial = true
      root.priorAddress = ""
      root.restoreOnBlur = false
      return
    }
    if (text.indexOf("special ") === 0) {
      var specialAddr = root.hexAddress(text.slice("special ".length))
      if (!specialAddr)
        return
      if (blurCapture.token !== root.blurToken) {
        Quickshell.execDetached([root.helper("blur-focus"), "--release", specialAddr])
        return
      }
      root.rememberSpecial(specialAddr)
      return
    }
    if (text.indexOf("hidden ") === 0) {
      if (blurCapture.token !== root.blurToken)
        return
      var hiddenName = text.slice("hidden ".length).trim()
      if (/^[A-Za-z0-9_-]{1,64}$/.test(hiddenName))
        root.rememberHidden(hiddenName)
      return
    }
    var addr = root.hexAddress(text)
    if (!addr)
      return
    if (blurCapture.token !== root.blurToken) {
      if (addr !== root.priorAddress)
        Quickshell.execDetached([root.helper("blur-focus"), "--release", addr])
      return
    }
    if (root.priorWasSpecial)
      return
    if (root.opening || (root.opened && !root.priorAddress)) {
      root.priorAddress = addr
      return
    }
    if (root.restoreOnBlur && !root.opened) {
      root.restoreOnBlur = false
      root.scheduleRestore(addr)
      return
    }
    if (!root.opened)
      Quickshell.execDetached([root.helper("blur-focus"), "--release", addr])
  }

  function eventAddress(data) {
    var text = String(data || "")
    var match = text.match(/0x[0-9a-fA-F]{1,32}/)
    if (match)
      return root.hexAddress(match[0])
    return root.hexAddress(text)
  }

  // Screencopy and the shell can take active focus after open, and Esc then
  // falls through to the quake console. keyCatcher is zero-size and is not
  // stacked over the cards, so this reclaim never blocks the pointer. Keep it
  // for the whole time the grid is open. Do not shrink it back to a short burst.
  function reclaimFocus() {
    if (!root.opened || root.hiding)
      return
    focusDebounce.tries = 0
    focusDebounce.restart()
  }

  function playReveal() {
    root.reveal = 0.96
    Qt.callLater(function() {
      if (root.opened)
        root.reveal = 1
    })
  }

  function close() {
    var wasActive = root.opened || root.opening
    var prior = ""
    if (!root.hiding && (root.opened || root.opening))
      prior = root.priorAddress
    if (root.priorWasSpecial)
      prior = ""
    if (!root.hiding && root.opening && !prior && !root.priorWasSpecial)
      root.restoreOnBlur = true
    root.priorAddress = ""
    root.blurAgain = false
    root.opening = false
    root.opened = false
    root.surfaceShown = false
    root.reveal = 0.96
    root.pointerHold = false
    root.heldIndex = -1
    root.heldAddress = ""
    root.pressedAddress = ""
    root.deferredRefresh = false
    root.hoverIgnoreUntil = 0
    root.scrollerInteractive = false
    blurWait.stop()
    focusDebounce.stop()
    backdropTimer.stop()
    reconcileTimer.stop()
    // Shell hide does not go through dismiss. Disarm here when dismiss has
    // not already done it (dismiss sets hiding first). Put a hidden quake
    // console back on that path too.
    if (wasActive && !root.hiding) {
      root.disarmNoWarps()
      if (!root.specialsSettled)
        root.settleSpecials("dismiss", "")
    }
    if (!root.hiding)
      root.scheduleRestore(prior)
  }

  function dismiss() {
    if (root.hiding)
      return
    if (!root.opened && !root.opening)
      return
    root.disarmNoWarps()
    if (!root.specialsSettled)
      root.settleSpecials("dismiss", "")
    var prior = root.priorAddress
    if (root.priorWasSpecial)
      prior = ""
    // A blur that has not reported its address yet should still restore,
    // unless that client was the quake console.
    root.restoreOnBlur = root.opening && !prior && !root.priorWasSpecial
    root.priorAddress = ""
    root.hiding = true
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      try { root.shell.hide(root.pluginId) } catch (e) {}
    }
    root.hiding = false
    root.scheduleRestore(prior)
  }

  // Esc is accepted, then the grid hides. For a few hundred milliseconds the
  // shortcut stays armed so that same Esc cannot fall through to the quake console.
  function dismissFromEsc() {
    if (!root.opened) {
      if (root.swallowEsc)
        return
      return
    }
    root.swallowEsc = true
    escGuard.restart()
    root.dismiss()
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  function captureBackdrop() {
    // The blurred picture is built from the workspace's own windows, so it
    // does not need a shot of the screen. That shot would include the grid.
    if (!root.opened || root.hiding)
      return
    root.syncBackdrop()
  }

  function helper(name) {
    return root.pluginDir + "/helpers/" + name
  }

  // cursor:no_warps for the whole time the grid is up. The helper logs
  // arm/disarm to stderr. --gen makes a dismiss beat an arm that is still
  // in flight, so the option cannot stay on after the grid is gone.
  function armNoWarps() {
    root.warpGen = root.warpGen + 1
    Quickshell.execDetached([
      root.helper("blur-focus"),
      "--arm-no-warps",
      "--gen",
      String(root.warpGen)
    ])
  }

  function disarmNoWarps() {
    root.warpGen = root.warpGen + 1
    Quickshell.execDetached([
      root.helper("blur-focus"),
      "--disarm-no-warps",
      "--gen",
      String(root.warpGen)
    ])
  }

  function hexAddress(raw) {
    var text = String(raw || "").trim()
    if (text.indexOf("address:") === 0)
      text = text.slice(8)
    if (text.indexOf("0x") === 0 || text.indexOf("0X") === 0)
      text = text.slice(2)
    if (!/^[0-9a-fA-F]{1,32}$/.test(text))
      return ""
    return "0x" + text.toLowerCase()
  }

  function prettyApp(app, title) {
    return Labels.prettyApp(app, title)
  }

  // fcitx classic UI maps an XWayland surface while the shell holds keyboard
  // focus. It is not a window the user opened. Leave the daemon running.
  function isFcitxChrome(app, title) {
    var name = String(app || "").toLowerCase()
    if (name === "fcitx" || name === "fcitx5" || name.indexOf("fcitx5-") === 0)
      return true
    var text = String(title || "")
    return text === "Fcitx5 Input Window" || text === "Fcitx5 Tray Window" || text === "Fcitx5 Menu Window"
  }

  function workspaceName(workspace) {
    return Labels.workspaceName(workspace)
  }

  function isPagerWorkspace(name, id) {
    return Labels.isPagerWorkspace(name, id)
  }

  function readMonitorBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    var i
    for (i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "")
        next[fields[1]] = parseInt(fields[0], 10)
    }
    root.monitorBlocks = next
    if (root.opened)
      root.rebuildPages()
  }

  function gridMonitor() {
    var list = []
    try {
      if (Hyprland.monitors && Hyprland.monitors.values)
        list = Hyprland.monitors.values
    } catch (e) {
      list = []
    }
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && list[i].focused)
        return list[i]
    }
    try {
      if (Hyprland.focusedMonitor)
        return Hyprland.focusedMonitor
    } catch (e2) {}
    return list.length ? list[0] : null
  }

  function currentBlock() {
    var mon = root.gridMonitor()
    var name = mon ? String(mon.name || "") : ""
    if (name && root.monitorBlocks[name] !== undefined && !isNaN(root.monitorBlocks[name]))
      return root.monitorBlocks[name]
    var active = mon && mon.activeWorkspace ? Number(mon.activeWorkspace.id) : 0
    if (active > 0)
      return Math.floor((active - 1) / root.workspaceSlots)
    return 0
  }

  function blockOf(id) {
    return Labels.blockOf(id, root.workspaceSlots)
  }

  function slotOf(id) {
    return Labels.slotOf(id, root.workspaceSlots)
  }

  // The number Super+N and the bar use. Hyprland's id is the monitor block
  // times 10, plus this slot, so 14 is workspace 4 on the second monitor.
  function pageLabel(id) {
    return Labels.pageLabel(id, root.workspaceSlots)
  }

  // The workstation the monitor is showing. A special workspace such as the
  // quake console is not itself a workstation: it can be summoned over any of
  // them, so the card uses this id instead of the special name.
  function monitorActiveId(monitor) {
    if (!monitor)
      return 0
    var active = monitor.activeWorkspace
    if (active && Number(active.id) > 0)
      return Number(active.id)
    var ipc = monitor.lastIpcObject || {}
    var aws = ipc.activeWorkspace || null
    if (aws && Number(aws.id) > 0)
      return Number(aws.id)
    return 0
  }

  function monitorByIpcId(id) {
    var want = Number(id)
    if (isNaN(want))
      return null
    var list = []
    try {
      if (Hyprland.monitors && Hyprland.monitors.values)
        list = Hyprland.monitors.values
    } catch (e) {
      return null
    }
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && Number(list[i].id) === want)
        return list[i]
    }
    return null
  }

  function monitorIdOf(monitor, ipc) {
    if (monitor && monitor.id !== undefined && monitor.id !== null && String(monitor.id) !== "")
      return Number(monitor.id)
    if (ipc && ipc.monitor !== undefined && ipc.monitor !== null && String(ipc.monitor) !== "")
      return Number(ipc.monitor)
    return -1
  }

  // Hyprland layout pixels relative to the monitor. The overlay maps these
  // onto the screen it is covering.
  function windowBox(ipc, monitor) {
    var at = (ipc && ipc.at) || []
    var size = (ipc && ipc.size) || []
    var mx = monitor && monitor.x !== undefined ? Number(monitor.x) : 0
    var my = monitor && monitor.y !== undefined ? Number(monitor.y) : 0
    return {
      monitorId: root.monitorIdOf(monitor, ipc),
      bx: Number(at[0] || 0) - mx,
      by: Number(at[1] || 0) - my,
      bw: Number(size[0] || 0),
      bh: Number(size[1] || 0)
    }
  }

  function panelMonitor() {
    try {
      if (panel.screen && Hyprland.monitorFor)
        return Hyprland.monitorFor(panel.screen)
    } catch (e) {}
    return null
  }

  function backdropScale() {
    var mon = root.panelMonitor()
    var scale = mon && Number(mon.scale) > 0 ? Number(mon.scale) : 1
    var layoutW = mon ? Number(mon.width) / scale : 0
    var layoutH = mon ? Number(mon.height) / scale : 0
    if (!(layoutW > 0))
      layoutW = panel.width
    if (!(layoutH > 0))
      layoutH = panel.height
    return {
      sx: panel.width > 0 && layoutW > 0 ? panel.width / layoutW : 1,
      sy: panel.height > 0 && layoutH > 0 ? panel.height / layoutH : 1
    }
  }

  // The shell's current wallpaper, resolved the same way the desktop does.
  // A video has no still of its own, so the lock screen's poster is used.
  function resolveWallpaper() {
    root.wallpaperGen = root.wallpaperGen + 1
    if (wallpaperProc.running) {
      root.wallpaperAgain = true
      return
    }
    wallpaperProc.token = root.wallpaperGen
    wallpaperProc.running = true
  }

  function takeWallpaper(path, fromPoster, token) {
    if (token !== root.wallpaperGen)
      return
    path = String(path || "").trim()
    if (!path)
      return
    if (!fromPoster && Util.isVideoPath(path)) {
      root.requestPoster(path, token)
      return
    }
    if (Util.isVideoPath(path))
      return
    if (path === root.wallpaperPath)
      return
    root.wallpaperPath = path
  }

  function requestPoster(path, token) {
    if (!path)
      return
    if (posterProc.running) {
      root.posterAgain = true
      root.posterPending = path
      root.posterToken = token
      return
    }
    posterProc.token = token
    posterProc.command = ["bash", root.posterScript(), path]
    posterProc.running = true
  }

  function posterScript() {
    return (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins/lock/poster.sh"
  }

  function syncBackdrop() {
    if (!root.opened || root.hiding)
      return
    if (panel.width < 1 || panel.height < 1)
      return
    var mon = root.panelMonitor()
    var monId = mon && mon.id !== undefined ? Number(mon.id) : -1
    var scale = root.backdropScale()
    var page = root.workspacePage ? String(root.workspacePage) : ""
    var rows = []
    var windows = false
    // All is the wallpaper only. A numbered page is the windows on it, or
    // the wallpaper when that workstation has none.
    if (page) {
      rows = Labels.placeBackdrop(root.allWindows, Number(page), monId, scale.sx, scale.sy)
      windows = rows.length > 0
    }
    var parts = [windows ? page : "wallpaper"]
    var i
    if (windows) {
      for (i = 0; i < rows.length; i++)
        parts.push(rows[i].address + "@" + Math.round(rows[i].px) + "x" + Math.round(rows[i].py))
    }
    var key = parts.join("|")
    if (key === root.backdropShownKey && root.backdropWindows === windows)
      return
    root.backdropShownKey = key
    if (!root.backdropReady) {
      root.backdropInstant = true
      root.backdropFront = windows ? rows : []
      root.backdropShowFront = true
      root.backdropWindows = windows
      root.backdropInstant = false
      root.backdropReady = true
      return
    }
    if (!windows) {
      root.backdropWindows = false
      return
    }
    if (root.backdropShowFront) {
      root.backdropBack = rows
      root.backdropShowFront = false
    } else {
      root.backdropFront = rows
      root.backdropShowFront = true
    }
    root.backdropWindows = true
  }

  function monitorWorkspaceIdFrom(workspace, monitor, ipc) {
    var mon = monitor || (workspace && workspace.monitor) || null
    var id = root.monitorActiveId(mon)
    if (id > 0)
      return id
    if (!ipc || ipc.monitor === undefined || ipc.monitor === null || String(ipc.monitor) === "")
      return 0
    return root.monitorActiveId(root.monitorByIpcId(ipc.monitor))
  }

  function displayWorkspaceId(row) {
    return Labels.displayWorkspaceId(row)
  }

  function rowWorkspaceLabel(row) {
    return Labels.rowWorkspaceLabel(row, root.workspaceSlots)
  }

  // Hyprland id of a strip page, or empty when that workstation is not on this monitor.
  function pageForWorkspaceId(id) {
    return Labels.pageForWorkspaceId(id, root.pageNames)
  }

  function workspaceIdForSlot(slot) {
    return Labels.workspaceIdForSlot(slot, root.currentBlock(), root.workspaceSlots)
  }

  // All is page 0 and is not stored here. Entries are Hyprland workspace ids.
  function rebuildPages() {
    var list = []
    try {
      if (Hyprland.workspaces && Hyprland.workspaces.values)
        list = Hyprland.workspaces.values
    } catch (e) {
      list = []
    }
    var names = Labels.pageNamesFor(root.currentBlock(), root.workspaceSlots, list)
    root.pageNames = names
    if (root.workspacePage && names.indexOf(root.workspacePage) < 0)
      root.workspacePage = ""
  }

  // Filter the grid to one page. The desktop workspace stays put.
  function showWorkspacePage(page) {
    if (!root.opened || root.hiding || root.pointerHold)
      return
    page = page ? String(page) : ""
    if (page === root.workspacePage)
      return
    root.workspacePage = page
    root.selectedAddress = ""
    root.selectedIndex = -1
    root.selectionPinned = false
    root.applyFilter()
    scroller.contentY = 0
  }

  // delta -1 is toward All (left). delta +1 walks 1, 2, 3, … (right).
  function stepWorkspace(delta) {
    if (!root.opened || root.hiding || root.pointerHold || !delta)
      return
    root.rebuildPages()
    var names = root.pageNames || []
    var index = 0
    if (root.workspacePage) {
      var found = names.indexOf(root.workspacePage)
      index = found < 0 ? 0 : found + 1
    }
    var next = index + delta
    if (next < 0)
      next = 0
    if (next > names.length)
      next = names.length
    var page = next === 0 ? "" : String(names[next - 1] || "")
    root.showWorkspacePage(page)
  }

  function pushRow(rows, seen, map, row, wayland) {
    if (!row.address || seen[row.address])
      return
    seen[row.address] = true
    rows.push(row)
    if (wayland)
      map[row.address] = wayland
  }

  function snapshot() {
    var rows = []
    var seen = ({})
    var map = ({})
    var hypr = []
    try {
      if (Hyprland.toplevels && Hyprland.toplevels.values)
        hypr = Hyprland.toplevels.values
    } catch (e) {
      hypr = []
    }

    var i
    for (i = 0; i < hypr.length; i++) {
      var item = hypr[i]
      if (!item)
        continue
      if (item.address !== undefined && (item.wayland !== undefined || item.workspace !== undefined || item.lastIpcObject !== undefined)) {
        var ipc = item.lastIpcObject || {}
        var wayland = item.wayland || null
        var app = String((wayland && wayland.appId) || ipc.class || ipc.initialClass || "")
        var title = String(item.title || (wayland && wayland.title) || ipc.title || "")
        var ws = root.workspaceName(item.workspace)
        if (!ws && ipc.workspace)
          ws = String(ipc.workspace.name || ipc.workspace.id || "")
        var wsId = item.workspace && item.workspace.id !== undefined ? Number(item.workspace.id) : 0
        if (!(wsId > 0) && !(wsId < 0) && ipc.workspace && ipc.workspace.id !== undefined)
          wsId = Number(ipc.workspace.id)
        var box = root.windowBox(ipc, item.monitor)
        root.pushRow(rows, seen, map, {
          address: root.hexAddress(item.address),
          title: title || root.prettyApp(app),
          app: app,
          appLabel: root.prettyApp(app, title),
          workspace: ws,
          workspaceId: wsId,
          monitorWorkspaceId: root.monitorWorkspaceIdFrom(item.workspace, item.monitor, ipc),
          monitorId: box.monitorId,
          bx: box.bx,
          by: box.by,
          bw: box.bw,
          bh: box.bh,
          activated: !!item.activated
        }, wayland)
      } else {
        root.considerWayland(rows, seen, map, item)
      }
    }

    if (rows.length === 0) {
      var tops = []
      try {
        if (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
          tops = ToplevelManager.toplevels.values
      } catch (e2) {
        tops = []
      }
      for (i = 0; i < tops.length; i++)
        root.considerWayland(rows, seen, map, tops[i])
    }

    root.waylandByAddress = map
    return rows
  }

  function considerWayland(rows, seen, map, top) {
    if (!top)
      return
    var attached = top.HyprlandToplevel || null
    var app = String(top.appId || "")
    var title = String(top.title || "")
    var address = ""
    var ws = ""
    var ipc = {}
    var activated = !!top.activated
    if (attached) {
      address = root.hexAddress(attached.address)
      if (!title)
        title = String(attached.title || "")
      ws = root.workspaceName(attached.workspace)
      ipc = attached.lastIpcObject || {}
      if (!app)
        app = String(ipc.class || ipc.initialClass || "")
      if (!ws && ipc.workspace)
        ws = String(ipc.workspace.name || ipc.workspace.id || "")
      if (attached.activated !== undefined)
        activated = !!attached.activated
    }
    var wsId = attached && attached.workspace && attached.workspace.id !== undefined ? Number(attached.workspace.id) : 0
    if (!(wsId > 0) && !(wsId < 0) && ipc && ipc.workspace && ipc.workspace.id !== undefined)
      wsId = Number(ipc.workspace.id)
    var box = root.windowBox(ipc, attached ? attached.monitor : null)
    root.pushRow(rows, seen, map, {
      address: address,
      title: title || root.prettyApp(app),
      app: app,
      appLabel: root.prettyApp(app, title),
      workspace: ws,
      workspaceId: wsId,
      monitorWorkspaceId: root.monitorWorkspaceIdFrom(attached ? attached.workspace : null, attached ? attached.monitor : null, ipc),
      monitorId: box.monitorId,
      bx: box.bx,
      by: box.by,
      bw: box.bw,
      bh: box.bh,
      activated: activated
    }, top)
  }

  function refresh() {
    var rows = []
    try { rows = root.snapshot() } catch (e) { rows = [] }
    if (rows.length > 0) {
      root.publish(rows)
      return
    }
    root.startList()
  }

  function publish(rows) {
    var kept = []
    var i
    for (i = 0; i < rows.length; i++) {
      if (root.isFcitxChrome(rows[i].app, rows[i].title))
        continue
      kept.push(rows[i])
    }
    root.allWindows = kept
    root.rebuildPages()
    if (root.pointerHold) {
      // A press is in flight. Rebuilding the grid now would retarget the click.
      root.deferredRefresh = true
      root.syncSelection(root.windows)
      return
    }
    root.applyFilter()
  }

  function applyFilter() {
    var needle = root.filterText.toLowerCase()
    var out = []
    var i
    for (i = 0; i < root.allWindows.length; i++) {
      var row = root.allWindows[i]
      if (root.workspacePage) {
        var pageId = Number(root.workspacePage)
        if (root.displayWorkspaceId(row) !== pageId)
          continue
      }
      var hay = (row.title + " " + row.app + " " + row.appLabel + " " + root.rowWorkspaceLabel(row)).toLowerCase()
      if (!needle || hay.indexOf(needle) !== -1)
        out.push(row)
    }
    // Drop scrolling before the Repeater sees the new model. A press that
    // lands during that rebuild belongs to the card, not the Flickable.
    root.scrollerInteractive = false
    root.windows = out
    root.syncSelection(out)
    root.phase = "ready"
    root.errorText = ""
    root.thumbGeneration++
    root.armScroller()
    root.syncBackdrop()
  }

  function armScroller() {
    root.scrollerInteractive = false
    Qt.callLater(function() {
      if (root.opened && !root.hiding && root.phase === "ready")
        root.scrollerInteractive = true
    })
  }

  function indexOfAddress(rows, address) {
    var i
    for (i = 0; i < rows.length; i++) {
      if (rows[i].address === address)
        return i
    }
    return -1
  }

  function syncSelection(rows) {
    var found = -1
    if (root.pointerHold && root.heldAddress) {
      found = root.indexOfAddress(rows, root.heldAddress)
      if (found >= 0) {
        root.selectedIndex = found
        root.selectedAddress = root.heldAddress
      }
      return
    }
    if (root.selectedAddress)
      found = root.indexOfAddress(rows, root.selectedAddress)
    if (found < 0) {
      if (!root.selectionPinned) {
        // No card is selected until hover or a key move. The previously
        // focused window stays in the list, but its activated flag does not
        // preselect a card.
        found = -1
      } else if (rows.length) {
        found = root.selectedIndex
        if (found < 0)
          found = 0
        if (found >= rows.length)
          found = rows.length - 1
      } else {
        found = -1
      }
    }
    root.selectedIndex = found
    root.selectedAddress = found >= 0 ? rows[found].address : ""
    if (found >= 0)
      root.selectionPinned = true
    if (found >= 0 && !root.pointerHold)
      Qt.callLater(function() { root.ensureVisible(found) })
  }

  function beginPointer(index, address) {
    var clean = root.hexAddress(address)
    if (!clean)
      return
    root.pointerHold = true
    root.heldIndex = index
    root.heldAddress = clean
    root.pressedAddress = clean
    root.hoverIgnoreUntil = Date.now() + 150
    root.selectionPinned = true
    root.selectedIndex = index
    root.selectedAddress = clean
    root.reclaimFocus()
  }

  function endPointerHold() {
    var apply = root.deferredRefresh && root.opened && !root.hiding
    root.pointerHold = false
    root.heldIndex = -1
    root.heldAddress = ""
    root.deferredRefresh = false
    if (apply)
      root.applyFilter()
  }

  function moveSelection(delta) {
    if (!root.windows.length)
      return
    var next
    if (root.selectedIndex < 0)
      next = delta < 0 ? root.windows.length - 1 : 0
    else {
      next = root.selectedIndex + delta
      if (next < 0)
        next = 0
      if (next >= root.windows.length)
        next = root.windows.length - 1
    }
    root.selectionPinned = true
    root.selectedIndex = next
    root.selectedAddress = root.windows[next].address
    root.ensureVisible(next)
  }

  function ensureVisible(index) {
    if (!root.opened || root.hiding)
      return
    var row = Math.floor(index / root.columns)
    var y = row * (root.cardHeight + root.gap)
    var view = scroller.height
    if (y < scroller.contentY)
      scroller.contentY = y
    else if (y + root.cardHeight > scroller.contentY + view)
      scroller.contentY = Math.max(0, y + root.cardHeight - view)
  }

  function setFilter(next) {
    root.filterText = next
    if (root.selectedIndex < 0) {
      root.selectionPinned = false
      root.selectedAddress = ""
    } else {
      root.selectionPinned = true
      root.selectedAddress = ""
    }
    root.applyFilter()
    root.reclaimFocus()
  }

  // The address was chosen on press. Focus and dismiss happen on release so a
  // warp cannot retarget the card, and the click cannot land on the desktop
  // while the grid is already gone.
  function finishCardPress() {
    if (!root.pointerHold && !root.pressedAddress)
      return
    var cardAddress = String(root.pressedAddress || "")
    root.pressedAddress = ""
    root.endPointerHold()
    if (cardAddress)
      root.activateAddress(cardAddress)
  }

  function activateAddress(address) {
    var clean = root.hexAddress(address)
    if (!clean)
      return
    var prior = root.priorAddress
    if (root.priorWasSpecial)
      prior = ""
    root.priorAddress = ""
    root.restoreOnBlur = false
    // Show the quake workspace again when the card is one of its windows.
    // A normal card leaves the hidden specials hidden and clears their blur.
    root.settleSpecials("activate", clean)
    if (prior && prior !== clean)
      Quickshell.execDetached([root.helper("focus-window"), clean, prior])
    else
      Quickshell.execDetached([root.helper("focus-window"), clean])
    // Press already chose the window. Disarm before dismiss so no_warps
    // cannot stay on. focus-window turns it on only for its own focus, then
    // reconciles to this disarm.
    root.disarmNoWarps()
    root.dismiss()
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.windows.length)
      return
    root.activateAddress(root.windows[index].address)
  }

  function closeAddress(address) {
    var clean = root.hexAddress(address)
    if (!clean)
      return
    Quickshell.execDetached([root.helper("close-window"), clean])
    if (clean === root.priorAddress) {
      root.priorAddress = ""
      Quickshell.execDetached([root.helper("blur-focus"), "--release", clean])
    }
    var kept = []
    var i
    for (i = 0; i < root.allWindows.length; i++) {
      if (root.allWindows[i].address !== clean)
        kept.push(root.allWindows[i])
    }
    root.allWindows = kept
    if (root.pointerHold)
      root.deferredRefresh = true
    else
      root.applyFilter()
    // Stay open. Reconcile once the compositor has had a chance to drop it.
    reconcileTimer.restart()
  }

  function closeIndex(index) {
    if (index < 0 || index >= root.windows.length)
      return
    root.closeAddress(root.windows[index].address)
  }

  // Super+W and Super+Q while the grid is open. No card is selected until
  // hover or the arrow keys, and this does not close the window behind the grid.
  function closeSelected() {
    if (!root.opened || root.hiding)
      return
    root.closeIndex(root.selectedIndex)
  }

  // Super+Shift+number while the grid is open. Same slots as Omarchy:
  // 1-9, and 10 on the 0 key. Nothing selected does not move the window
  // behind the grid. The desktop follows the card, as the normal chord does.
  function moveSelectedToSlot(slot) {
    if (!root.opened || root.hiding || root.pointerHold)
      return
    if (root.selectedIndex < 0 || root.selectedIndex >= root.windows.length)
      return
    var row = root.windows[root.selectedIndex]
    var address = root.hexAddress(row && row.address)
    var id = root.workspaceIdForSlot(slot)
    if (!address || !id)
      return
    Quickshell.execDetached([
      "hyprctl", "dispatch",
      "hl.dsp.window.move({ workspace = \"" + id + "\", follow = true, window = \"address:" + address + "\" })"
    ])
    // The toplevel list still has the old workstation until movewindowv2.
    // All reads allWindows, so point the card at the new id now. The event
    // confirms it. A refresh here would put the old number back.
    root.rebuildPages()
    root.workspacePage = String(id)
    root.selectedAddress = address
    root.selectionPinned = true
    var status = root.noteWindowMovedParts([address, String(id), String(id)])
    // Already on that workstation: the card did not change, but the page did.
    if (status !== "updated")
      root.applyFilter()
  }

  function moveEventParts(event) {
    var parts = []
    try {
      if (event && event.parse)
        parts = event.parse(3)
    } catch (e) {
      parts = []
    }
    if (parts && parts.length)
      return parts
    return String((event && event.data) || "").split(",")
  }

  // A window changed workstations. Update that one card from the event so
  // All shows the new number without closing the grid. The in-process
  // toplevel snapshot is often still the previous workstation.
  function noteWindowMoved(event) {
    root.noteWindowMovedParts(root.moveEventParts(event))
  }

  function noteWindowMovedParts(parts) {
    var address = root.hexAddress(parts && parts.length ? parts[0] : "")
    var id = Labels.movedWorkspaceId(parts)
    var result = Labels.retargetWindow(root.allWindows, address, id)
    if (result.status === "updated") {
      root.allWindows = result.rows
      if (root.pointerHold) {
        root.deferredRefresh = true
        return result.status
      }
      root.applyFilter()
      return result.status
    }
    if (result.status === "same")
      return result.status
    root.refresh()
    return result.status
  }

  function handleCustom(token) {
    if (token === "timsonner.nitty-griddy:open")
      root.open("{}")
    else if (token === "timsonner.nitty-griddy:close")
      root.dismiss()
    else if (token === "timsonner.nitty-griddy:toggle")
      root.toggle()
    else if (token === "timsonner.nitty-griddy:workspace-prev")
      root.stepWorkspace(-1)
    else if (token === "timsonner.nitty-griddy:workspace-next")
      root.stepWorkspace(1)
    else if (token === "timsonner.nitty-griddy:close-selected")
      root.closeSelected()
    else if (token.indexOf("timsonner.nitty-griddy:move-to-") === 0)
      root.moveSelectedToSlot(token.substring("timsonner.nitty-griddy:move-to-".length))
  }

  function startList() {
    if (listProc.running)
      return
    root.pendingClients = []
    root.clientSnapshotRejected = false
    listProc.running = true
  }

  function addClientLine(raw) {
    var line = String(raw || "")
    if (!line.length)
      return
    if (line.length > 4096 || root.pendingClients.length >= 256) {
      root.clientSnapshotRejected = true
      return
    }
    try {
      var row = JSON.parse(line)
      var address = root.hexAddress(row && row.address)
      if (!address) {
        root.clientSnapshotRejected = true
        return
      }
      var app = String((row && (row.class || row.initialClass)) || "")
      var title = String((row && row.title) || "")
      root.pendingClients.push({
        address: address,
        title: title || root.prettyApp(app),
        app: app,
        appLabel: root.prettyApp(app, title),
        workspace: String((row && row.workspace) || ""),
        workspaceId: Number((row && row.workspaceId) || 0),
        monitorWorkspaceId: Number((row && row.monitorWorkspaceId) || 0),
        monitorId: Number((row && row.monitorId) || -1),
        bx: Number((row && row.bx) || 0),
        by: Number((row && row.by) || 0),
        bw: Number((row && row.bw) || 0),
        bh: Number((row && row.bh) || 0),
        activated: false
      })
    } catch (e) {
      root.clientSnapshotRejected = true
    }
  }

  function finishList(exitCode) {
    if (!root.opened)
      return
    var live = []
    try { live = root.snapshot() } catch (e) { live = [] }
    if (live.length > 0) {
      root.publish(live)
      return
    }
    if (exitCode === 0 && !root.clientSnapshotRejected) {
      root.waylandByAddress = ({})
      root.publish(root.pendingClients.slice())
      return
    }
    root.phase = "error"
    root.errorText = "Hyprland didn’t return a window list."
    root.scrollerInteractive = false
    root.windows = []
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      if (root.opened)
        root.dismissFromEsc()
      return
    }
    if (!root.opened)
      return
    event.accepted = true
    if (event.key === Qt.Key_Left) {
      root.moveSelection(-1)
    } else if (event.key === Qt.Key_Right) {
      root.moveSelection(1)
    } else if (event.key === Qt.Key_Up) {
      root.moveSelection(-root.columns)
    } else if (event.key === Qt.Key_Down) {
      root.moveSelection(root.columns)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activateIndex(root.selectedIndex)
    } else if (event.key === Qt.Key_Backspace) {
      if (root.filterText.length)
        root.setFilter(root.filterText.slice(0, root.filterText.length - 1))
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
               && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
      root.setFilter(root.filterText + event.text)
    } else {
      event.accepted = false
    }
  }

  Timer {
    id: escGuard
    interval: 350
    repeat: false
    onTriggered: root.swallowEsc = false
  }

  Timer {
    id: focusDebounce
    interval: 40
    repeat: true
    property int tries: 0
    onTriggered: {
      var win = panel.contentItem ? panel.contentItem.window : null
      // Item focus alone is not enough: another window of the shell process
      // (screencopy, the bar) can hold Qt's focusWindow, and keys then route
      // there and vanish. The window itself has to be Qt-active too.
      if (!root.opened || root.hiding || !win || (keyCatcher.activeFocus && win.active)) {
        stop()
        return
      }
      if (win && !win.active)
        win.requestActivate()
      keyCatcher.forceActiveFocus()
      tries++
      if (tries > 20)
        stop()
    }
  }

  Timer {
    id: backdropTimer
    interval: 30
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!root.opened || panel.contentRevealed || tries > 8) {
        stop()
        return
      }
      tries++
      root.captureBackdrop()
    }
  }

  Timer {
    id: reconcileTimer
    interval: 250
    repeat: false
    onTriggered: if (root.opened) root.refresh()
  }

  // If hyprctl does not return, still show the grid. The blur may land late.
  Timer {
    id: blurWait
    interval: 400
    repeat: false
    onTriggered: root.finishBlur()
  }

  Connections {
    target: panel
    function onContentRevealedChanged() {
      if (panel.contentRevealed && root.opened) {
        root.playReveal()
        root.reclaimFocus()
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event)
        return
      var name = String(event.name || "")
      var data = String(event.data || "").trim()
      if (name === "custom")
        root.handleCustom(data)
      else if (name.indexOf("timsonner.nitty-griddy:") === 0)
        root.handleCustom(name)
      else if (name === "closewindow") {
        var gone = root.eventAddress(data)
        if (gone && gone === root.priorAddress)
          root.priorAddress = ""
        if (root.opened)
          root.refresh()
      } else if (root.opened && (name === "openwindow" || name === "windowtitle" || name === "windowtitlev2"))
        root.refresh()
      else if (root.opened && (name === "movewindow" || name === "movewindowv2"))
        root.noteWindowMoved(event)
      else if (root.opened && (name === "createworkspace" || name === "destroyworkspace"))
        root.rebuildPages()
    }
  }

  Connections {
    target: Hyprland.workspaces
    ignoreUnknownSignals: true
    function onObjectInsertedPost() { if (root.opened) root.rebuildPages() }
    function onObjectRemovedPost() { if (root.opened) root.rebuildPages() }
  }

  Connections {
    target: Hyprland.toplevels
    ignoreUnknownSignals: true
    function onObjectInsertedPost() { if (root.opened) root.refresh() }
    function onObjectRemovedPost() { if (root.opened) root.refresh() }
  }

  Process {
    id: wallpaperProc
    property int token: 0
    command: [
      "bash", "-c",
      'target=$(readlink -f "$1"); if [[ -e $target ]]; then printf "%s\\n" "$target"; else ' +
      'find "$2" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) | sort | head -n 1; fi',
      "resolve", root.wallpaperLink, root.themeBackgrounds
    ]
    stdout: StdioCollector {
      onStreamFinished: root.takeWallpaper(String(text || "").trim(), false, wallpaperProc.token)
    }
    onExited: function(exitCode) {
      if (!root.wallpaperAgain)
        return
      root.wallpaperAgain = false
      wallpaperProc.token = root.wallpaperGen
      wallpaperProc.running = true
    }
  }

  Process {
    id: posterProc
    property int token: 0
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: root.takeWallpaper(String(text || "").trim(), true, posterProc.token)
    }
    onExited: function(exitCode) {
      if (!root.posterAgain)
        return
      root.posterAgain = false
      posterProc.token = root.posterToken
      posterProc.command = ["bash", root.posterScript(), root.posterPending]
      posterProc.running = true
    }
  }

  Component.onCompleted: root.resolveWallpaper()

  Process {
    id: listProc
    command: [root.helper("list-windows")]
    stdout: SplitParser {
      onRead: function(line) { root.addClientLine(line) }
    }
    onExited: function(exitCode) { root.finishList(exitCode) }
  }

  Process {
    id: blurCapture
    property int token: 0
    command: [root.helper("blur-focus")]
    stdout: SplitParser {
      onRead: function(line) { root.noteBlurAddress(line) }
    }
    onExited: function(exitCode) {
      if (root.blurAgain) {
        root.launchBlur()
        return
      }
      if (token === root.blurToken)
        root.finishBlur()
    }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readMonitorBlocks(text())
    onLoadFailed: root.readMonitorBlocks("")
  }

  IpcHandler {
    target: "timsonner.nitty-griddy"
    function open(): string {
      root.open("{}")
      return "ok"
    }
    function close(): string {
      root.dismiss()
      return "ok"
    }
    function toggle(): string {
      root.toggle()
      return "ok"
    }
  }

  OverlayWindow {
    id: panel
    shown: root.surfaceShown
    shownKeyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    // Request the exclusive keyboard grab directly on the surface too. Going
    // only through the wrapper's shownKeyboardFocus binding left this surface
    // without keyboard enter after remaps, so Esc and typing never arrived.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "timsonner-nitty-griddy"
    // The shell overlay defaults to a transparent surface. A transparent pixel
    // with no input grab is a hole onto the desktop behind the grid.
    color: root.scrim

    Shortcut {
      sequences: ["Esc"]
      enabled: root.opened || root.swallowEsc
      context: Qt.ApplicationShortcut
      onActivated: root.dismissFromEsc()
    }

    Shortcut {
      sequence: StandardKey.Cancel
      enabled: root.opened || root.swallowEsc
      context: Qt.ApplicationShortcut
      onActivated: root.dismissFromEsc()
    }

    Item {
      id: stage
      anchors.fill: parent

      // Backdrop fade only. The scrim, the dismiss layer, and the cards are
      // siblings of this item so a second summon can take presses while
      // contentRevealed is still false and this layer is still opacity 0.
      Item {
        id: visualStage
        anchors.fill: parent
        enabled: false
        clip: true
        opacity: panel.contentRevealed ? root.reveal : 0
        scale: panel.contentRevealed ? root.reveal : 0.97
        onWidthChanged: if (root.opened) root.syncBackdrop()
        onHeightChanged: if (root.opened) root.syncBackdrop()

        // Under the window pictures. All, and a workstation with no windows,
        // leave those pictures clear so this is what you see.
        Item {
          anchors.fill: parent

          BackgroundMedia {
            id: wallpaper
            anchors.fill: parent
            path: root.wallpaperPath
            cached: true
            constrainDecode: true
            decodeSize: Qt.size(width, height)
          }

          MultiEffect {
            anchors.fill: parent
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: wallpaper.ready
            blur: 0.75
            blurMax: 64
            blurMultiplier: 1.1
            visible: wallpaper.ready
            opacity: wallpaper.ready && !root.backdropWindows ? 1 : 0
            Behavior on opacity {
              NumberAnimation {
                duration: Style.duration(180)
                easing.type: Easing.Bezier
                easing.bezierCurve: Style.easeOut
              }
            }
          }
        }

        // One field for the picture on screen, one for the picture fading in.
        Component {
          id: backdropField
          Item {
            property var windows: []
            Repeater {
              model: windows
              delegate: Item {
                required property var modelData
                x: modelData.px
                y: modelData.py
                width: Math.max(1, modelData.pw)
                height: Math.max(1, modelData.ph)

                ScreencopyView {
                  id: piece
                  anchors.fill: parent
                  enabled: false
                  opacity: 0
                  captureSource: root.opened ? (root.waylandByAddress[modelData.address] || null) : null
                  live: false
                  paintCursor: false
                  onCaptureSourceChanged: if (captureSource) captureFrame()
                  Component.onCompleted: if (captureSource) captureFrame()
                }

                MultiEffect {
                  anchors.fill: parent
                  source: piece
                  autoPaddingEnabled: true
                  blurEnabled: piece.hasContent
                  blur: 0.55
                  blurMax: 48
                  visible: piece.hasContent
                }
              }
            }
          }
        }

        Loader {
          anchors.fill: parent
          sourceComponent: backdropField
          active: root.opened
          opacity: root.backdropShowFront && root.backdropWindows ? 1 : 0
          Behavior on opacity {
            enabled: !root.backdropInstant
            NumberAnimation {
              duration: Style.duration(180)
              easing.type: Easing.Bezier
              easing.bezierCurve: Style.easeOut
            }
          }
          onLoaded: item.windows = Qt.binding(function() { return root.backdropFront })
        }

        Loader {
          anchors.fill: parent
          sourceComponent: backdropField
          active: root.opened
          opacity: !root.backdropShowFront && root.backdropWindows ? 1 : 0
          Behavior on opacity {
            enabled: !root.backdropInstant
            NumberAnimation {
              duration: Style.duration(180)
              easing.type: Easing.Bezier
              easing.bezierCurve: Style.easeOut
            }
          }
          onLoaded: item.windows = Qt.binding(function() { return root.backdropBack })
        }
      }

      Rectangle {
        id: inputScrim
        z: 1
        anchors.fill: parent
        opacity: 1
        color: root.scrim
      }

      MouseArea {
        id: backdropDismiss
        z: 1
        anchors.fill: parent
        preventStealing: true
        // Take the press, and dismiss on release. Closing on press unmapped the
        // grid while the button was still down, so the click landed on the
        // window behind it.
        onPressed: function(mouse) {
          mouse.accepted = true
        }
        onReleased: function(mouse) {
          mouse.accepted = true
          if (containsMouse)
            root.dismiss()
        }
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        height: Style.space(92)
        z: 3

        // Title and subtitle are plain text. This catcher stops above the
        // strip so it cannot take a workstation number's press.
        MouseArea {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: pageStrip.top
          preventStealing: true
          onPressed: function(mouse) { mouse.accepted = true }
        }

        Text {
          id: titleLabel
          textFormat: Text.PlainText
          text: "NittyGriddy"
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.heading
          font.bold: true
          anchors.left: parent.left
          anchors.top: parent.top
        }

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.top: titleLabel.bottom
          anchors.topMargin: Style.space(2)
          anchors.right: parent.right
          elide: Text.ElideRight
          color: root.foreground
          opacity: 0.72
          font.family: root.uiFont
          font.pixelSize: Style.font.body
          text: {
            if (root.filterText)
              return "Filter: " + root.filterText
            if (root.phase === "loading")
              return "Gathering windows…"
            if (root.phase === "error")
              return root.errorText
            if (!root.windows.length && root.filterText === "" && root.workspacePage === "" && root.allWindows.length === 0)
              return "No open windows"
            var noun = root.windows.length === 1 ? "window" : "windows"
            var where = root.workspacePage ? ("workspace " + root.pageLabel(root.workspacePage)) : "all workspaces"
            return root.windows.length + " " + noun + " · " + where
          }
        }

        Flickable {
          id: pageStrip
          z: 2
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(28)
          contentWidth: pageRow.width
          contentHeight: height
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentWidth > width + 1
          clip: true

          // Gaps between the numbers. A miss here used to reach the backdrop.
          MouseArea {
            z: 0
            width: Math.max(pageStrip.width, pageRow.width)
            height: pageStrip.height
            preventStealing: true
            onPressed: function(mouse) { mouse.accepted = true }
          }

          Row {
            id: pageRow
            z: 1
            spacing: Style.space(8)
            height: pageStrip.height

            Repeater {
              model: 1 + root.pageNames.length
              delegate: MouseArea {
                required property int index
                readonly property string pageId: index === 0 ? "" : String(root.pageNames[index - 1] || "")
                readonly property bool current: pageId === root.workspacePage
                width: Math.max(chip.implicitWidth + Style.space(12), Style.space(28))
                height: pageStrip.height
                preventStealing: true
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: function(mouse) {
                  mouse.accepted = true
                  root.showWorkspacePage(pageId)
                }

                Text {
                  id: chip
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: index === 0 ? "All" : root.pageLabel(pageId)
                  color: current ? root.accent : root.foreground
                  opacity: current ? 1 : 0.5
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  font.bold: current
                }
              }
            }
          }
        }
      }

      Flickable {
        id: scroller
        anchors.top: header.bottom
        anchors.bottom: hint.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: Style.space(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Tall grids still scroll. Scrolling stays off through publish and one
        // beat after, and a short pressDelay lets the card take the press
        // before this view can treat it as a flick.
        interactive: root.scrollerInteractive && contentHeight > height + 1
        pressDelay: 64
        contentWidth: width
        contentHeight: Math.max(height, grid.height)
        z: 3

        Grid {
          id: grid
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.columns * root.cardWidth + Math.max(0, root.columns - 1) * root.gap
          columns: root.columns
          columnSpacing: root.gap
          rowSpacing: root.gap

          Repeater {
            model: root.windows.length
            delegate: Rectangle {
              required property int index
              readonly property var row: (index >= 0 && index < root.windows.length) ? root.windows[index] : null
              readonly property bool selected: row && index === root.selectedIndex
              readonly property string address: row ? String(row.address || "") : ""
              width: root.cardWidth
              height: root.cardHeight
              radius: root.radius
              clip: true
              color: root.background
              border.width: selected ? Math.max(2, Style.space(2)) : 1
              border.color: selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              opacity: row ? (selected ? 1 : 0.94) : 0

              Item {
                id: thumb
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.margins: Style.space(8)
                clip: true

                ScreencopyView {
                  id: preview
                  anchors.fill: parent
                  enabled: false
                  captureSource: root.opened ? (root.waylandByAddress[address] || null) : null
                  live: false
                  paintCursor: false
                  constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
                  visible: hasContent
                  onCaptureSourceChanged: if (captureSource) captureFrame()
                  Component.onCompleted: if (captureSource) captureFrame()
                }

                Connections {
                  target: root
                  function onThumbGenerationChanged() {
                    if (preview.captureSource)
                      preview.captureFrame()
                  }
                }

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(16)
                  spacing: Style.space(4)
                  visible: !preview.hasContent

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row ? row.appLabel : ""
                    color: root.foreground
                    font.family: root.uiFont
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row ? row.title : ""
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.uiFont
                    font.pixelSize: Style.font.body
                  }
                }
              }

              Rectangle {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(52)
                color: selected ? root.selectedFill : "transparent"
                radius: root.radius

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row ? row.appLabel : ""
                    color: root.accent
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Item {
                    width: parent.width
                    height: Math.max(titleLine.implicitHeight, workspaceLine.implicitHeight)

                    // The number stays on the right. A long title elides before it.
                    Text {
                      id: workspaceLine
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: implicitWidth
                      horizontalAlignment: Text.AlignRight
                      z: 1
                      textFormat: Text.PlainText
                      text: row ? root.rowWorkspaceLabel(row) : ""
                      visible: text.length > 0
                      color: root.foreground
                      font.family: root.uiFont
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      id: titleLine
                      anchors.left: parent.left
                      anchors.right: workspaceLine.visible ? workspaceLine.left : parent.right
                      anchors.rightMargin: workspaceLine.visible ? Style.space(8) : 0
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: row ? String(row.title || "") : ""
                      color: root.foreground
                      font.family: root.uiFont
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }

              Rectangle {
                id: closeButton
                visible: selected || closeHover.containsMouse
                width: Style.space(28)
                height: Style.space(28)
                radius: width / 2
                color: closeHover.containsMouse ? Commons.Color.urgent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(10)
                z: 5

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "×"
                  color: closeHover.containsMouse ? Commons.Color.background : root.foreground
                  font.family: root.uiFont
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                MouseArea {
                  id: closeHover
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var cardAddress = String(address || "")
                    root.beginPointer(index, cardAddress)
                    root.closeAddress(cardAddress)
                    root.endPointerHold()
                    // Closing is not a focus. Leave the address clear so a later
                    // release cannot activate the window that was just closed.
                    root.pressedAddress = ""
                  }
                }
              }

              // Above the card press. The number is plain text in the footer, and
              // the card press underneath would otherwise focus that window.
              MouseArea {
                id: workspaceHit
                z: 6
                visible: workspaceLine.visible
                enabled: workspaceLine.visible
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Style.space(4)
                anchors.bottomMargin: Style.space(4)
                width: Math.max(Style.space(28), workspaceLine.implicitWidth + Style.space(16))
                height: Math.max(Style.space(28), workspaceLine.implicitHeight + Style.space(12))
                preventStealing: true
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: function(mouse) {
                  mouse.accepted = true
                  var page = root.pageForWorkspaceId(root.displayWorkspaceId(row))
                  if (page)
                    root.showWorkspacePage(page)
                }
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                z: 2
                onEntered: {
                  if (!row || root.pointerHold || Date.now() < root.hoverIgnoreUntil)
                    return
                  root.selectionPinned = true
                  root.selectedIndex = index
                  root.selectedAddress = address
                  root.reclaimFocus()
                }
                onPressed: function(mouse) {
                  if (!row)
                    return
                  mouse.accepted = true
                  // Remember the card now. The release focuses it, so a warp
                  // cannot choose a different one and the click stays on the grid.
                  root.beginPointer(index, String(address || ""))
                }
                onReleased: function(mouse) {
                  mouse.accepted = true
                  root.finishCardPress()
                }
                onCanceled: root.finishCardPress()
              }
            }
          }
        }

        Column {
          anchors.centerIn: parent
          width: parent.width
          spacing: Style.space(8)
          visible: root.windows.length === 0
          z: 2

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.font.title
            text: root.phase === "error"
                  ? root.errorText
                  : (root.phase === "loading"
                     ? "Gathering windows…"
                     : (root.filterText
                        ? "Nothing matches that filter."
                        : (root.workspacePage
                           ? "No windows on workspace " + root.pageLabel(root.workspacePage)
                           : (root.allWindows.length ? "Nothing matches that filter." : "No open windows"))))
          }
        }
      }

      Text {
        id: hint
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: root.pad
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.66
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        text: "Type to filter · Arrow keys to move · Enter to focus · Super+W or Super+Q to close · Esc to dismiss · Super+Tab or swipe for workspace"
        z: 3
      }

      // Zero-size on purpose. A full-bleed catcher above the grid was taking
      // pointer hits, so clicks missed the card under the cursor.
      Item {
        id: keyCatcher
        width: 0
        height: 0
        focus: root.opened
        Keys.onPressed: function(event) { root.handleKey(event) }
        onActiveFocusChanged: {
          if (root.opened && !root.hiding && !activeFocus)
            root.reclaimFocus()
        }
      }
    }
  }
}
