import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// NittyGriddy overlay for Omarchy Quattro.
// The shell calls open(payloadJson) on summon and close() on hide.
// keepLoaded keeps this item mounted, so socket2 custom events and the
// tim.nitty-griddy IPC target are live before the first swipe.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "tim.nitty-griddy"
  readonly property string pluginDir: {
    var dir = (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
    if (!dir)
      dir = Quickshell.env("HOME") + "/.config/omarchy/plugins/tim.nitty-griddy"
    while (dir.length > 1 && dir.charAt(dir.length - 1) === "/")
      dir = dir.slice(0, dir.length - 1)
    return dir
  }

  property bool opened: false
  property bool surfaceShown: false
  property bool hiding: false
  property real reveal: 0.96
  property string filterText: ""
  property string phase: "ready"
  property string errorText: ""
  property var allWindows: []
  property var windows: []
  property var waylandByAddress: ({})
  property string selectedAddress: ""
  property int selectedIndex: -1
  property bool selectionPinned: false
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
  readonly property real viewHeight: Math.max(1, panel.height - pad * 2 - Style.space(96))
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
    root.opened = true
    root.surfaceShown = true
    // A previous summon can leave a hold, a deferred rebuild, or a scroll
    // offset. The next press then misses the card and only dismisses.
    root.pointerHold = false
    root.heldIndex = -1
    root.heldAddress = ""
    root.pressedAddress = ""
    root.deferredRefresh = false
    root.hoverIgnoreUntil = 0
    root.hiding = false
    root.scrollerInteractive = false
    root.filterText = ""
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

  // Screencopy and the shell can take active focus after open, and Esc then
  // falls through to the quake console. keyCatcher is zero-size and is not
  // stacked over the cards, so this reclaim never blocks the pointer. Keep it
  // for the whole time the grid is open — do not shrink it back to a short burst.
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
    focusDebounce.stop()
    backdropTimer.stop()
    reconcileTimer.stop()
  }

  function dismiss() {
    if (root.hiding)
      return
    root.hiding = true
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      try { root.shell.hide(root.pluginId) } catch (e) {}
    }
    root.hiding = false
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
    // Grab the desktop while the shell is still holding this surface at
    // opacity 0 (waiting for HiDPI scale). A later frame would include the grid.
    if (!root.opened || !panel.screen || panel.contentRevealed)
      return
    shot.captureFrame()
  }

  function helper(name) {
    return root.pluginDir + "/helpers/" + name
  }

  function hexAddress(raw) {
    var text = String(raw || "").trim()
    if (text.indexOf("address:") === 0)
      text = text.slice(8)
    if (text.indexOf("0x") === 0 || text.indexOf("0X") === 0)
      text = text.slice(2)
    if (!/^[0-9a-fA-F]{1,32}$/.test(text))
      return ""
    return "0x" + text
  }

  function prettyApp(app) {
    var text = String(app || "")
    var slash = text.lastIndexOf("/")
    if (slash >= 0)
      text = text.slice(slash + 1)
    var dot = text.lastIndexOf(".")
    if (dot >= 0 && dot < text.length - 1)
      text = text.slice(dot + 1)
    return text || "Window"
  }

  function workspaceName(workspace) {
    if (!workspace)
      return ""
    if (workspace.name !== undefined && String(workspace.name || "") !== "")
      return String(workspace.name)
    if (workspace.id !== undefined && workspace.id !== null && String(workspace.id) !== "")
      return String(workspace.id)
    return ""
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
        root.pushRow(rows, seen, map, {
          address: root.hexAddress(item.address),
          title: title || root.prettyApp(app),
          app: app,
          appLabel: root.prettyApp(app),
          workspace: ws,
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
    var activated = !!top.activated
    if (attached) {
      address = root.hexAddress(attached.address)
      if (!title)
        title = String(attached.title || "")
      ws = root.workspaceName(attached.workspace)
      var ipc = attached.lastIpcObject || {}
      if (!app)
        app = String(ipc.class || ipc.initialClass || "")
      if (!ws && ipc.workspace)
        ws = String(ipc.workspace.name || ipc.workspace.id || "")
      if (attached.activated !== undefined)
        activated = !!attached.activated
    }
    root.pushRow(rows, seen, map, {
      address: address,
      title: title || root.prettyApp(app),
      app: app,
      appLabel: root.prettyApp(app),
      workspace: ws,
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
    root.allWindows = rows
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
      var hay = (row.title + " " + row.app + " " + row.appLabel + " " + row.workspace).toLowerCase()
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
    var i
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
        found = rows.length ? 0 : -1
        for (i = 0; i < rows.length; i++) {
          if (rows[i].activated) {
            found = i
            break
          }
        }
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
    var index = root.selectedIndex
    if (index < 0)
      index = 0
    var next = index + delta
    if (next < 0)
      next = 0
    if (next >= root.windows.length)
      next = root.windows.length - 1
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
    root.selectionPinned = true
    root.selectedAddress = ""
    root.applyFilter()
    root.reclaimFocus()
  }

  function activateAddress(address) {
    var clean = root.hexAddress(address)
    if (!clean)
      return
    Quickshell.execDetached([root.helper("focus-window"), clean])
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

  function handleCustom(token) {
    if (token === "tim.nitty-griddy:open")
      root.open("{}")
    else if (token === "tim.nitty-griddy:close")
      root.dismiss()
    else if (token === "tim.nitty-griddy:toggle")
      root.toggle()
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
        appLabel: root.prettyApp(app),
        workspace: String((row && row.workspace) || ""),
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
    } else if ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Q) {
      root.closeIndex(root.selectedIndex)
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
      if (!root.opened || root.hiding || keyCatcher.activeFocus) {
        stop()
        return
      }
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
      else if (name.indexOf("tim.nitty-griddy:") === 0)
        root.handleCustom(name)
      else if (root.opened && (name === "openwindow" || name === "closewindow" || name === "windowtitle" || name === "movewindow"))
        root.refresh()
    }
  }

  Connections {
    target: Hyprland.toplevels
    ignoreUnknownSignals: true
    function onObjectInsertedPost() { if (root.opened) root.refresh() }
    function onObjectRemovedPost() { if (root.opened) root.refresh() }
  }

  Process {
    id: listProc
    command: [root.helper("list-windows")]
    stdout: SplitParser {
      onRead: function(line) { root.addClientLine(line) }
    }
    onExited: function(exitCode) { root.finishList(exitCode) }
  }

  IpcHandler {
    target: "tim.nitty-griddy"
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
    WlrLayershell.namespace: "tim-nitty-griddy"
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
        opacity: panel.contentRevealed ? root.reveal : 0
        scale: panel.contentRevealed ? root.reveal : 0.97

        ScreencopyView {
          id: shot
          z: -2
          // A full-screen capture of the monitor forwards pointer hits into the
          // real desktop. It is only a blur source, never an input target.
          enabled: false
          anchors.fill: parent
          opacity: 0
          visible: root.opened
          layer.enabled: root.opened
          captureSource: root.opened ? panel.screen : null
          live: false
          paintCursor: false
        }

        MultiEffect {
          z: -1
          anchors.fill: parent
          source: shot
          autoPaddingEnabled: true
          blurEnabled: shot.hasContent
          blur: 0.35
          blurMax: 32
          visible: shot.hasContent
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
        onPressed: function(mouse) {
          mouse.accepted = true
          root.dismiss()
        }
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        height: Style.space(58)
        z: 3

        Text {
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
          anchors.bottom: parent.bottom
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
            if (!root.windows.length && root.filterText === "" && root.allWindows.length === 0)
              return "No open windows"
            var noun = root.windows.length === 1 ? "window" : "windows"
            return root.windows.length + " " + noun + " · all workspaces"
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

                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: {
                      if (!row)
                        return ""
                      var title = String(row.title || "")
                      if (row.workspace)
                        return title + "  ·  " + row.workspace
                      return title
                    }
                    color: root.foreground
                    font.family: root.uiFont
                    font.pixelSize: Style.font.body
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
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
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
                  // Act on press. A warped release must not retarget this card.
                  var cardAddress = String(address || "")
                  root.beginPointer(index, cardAddress)
                  if (mouse.button === Qt.MiddleButton)
                    root.closeAddress(cardAddress)
                  else if (mouse.button === Qt.LeftButton)
                    root.activateAddress(cardAddress)
                  root.endPointerHold()
                }
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
                     : (root.allWindows.length ? "Nothing matches that filter." : "No open windows"))
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
        text: "Click or Enter focuses · type to filter · × / middle-click / Shift+Q closes · Esc dismisses"
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
