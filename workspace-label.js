// Workspace numbers for the grid. Hyprland ids come in blocks of 10 per
// monitor. The card and the strip show the slot, so id 14 is workspace 4.
// A special workspace is not a workstation.

function slotOf(id, slots) {
  return (Number(id) - 1) % slots + 1
}

function blockOf(id, slots) {
  return Math.floor((Number(id) - 1) / slots)
}

function pageLabel(id, slots) {
  var n = Number(id)
  if (!(n > 0))
    return ""
  return String(slotOf(n, slots))
}

function workspaceIdForSlot(slot, block, slots) {
  var n = parseInt(slot, 10)
  if (!(n >= 1 && n <= slots))
    return 0
  return block * slots + n
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

function isPagerWorkspace(name, id) {
  var text = String(name || "")
  if (text.indexOf("special:") === 0)
    return false
  if (id !== undefined && id !== null && id !== "" && Number(id) < 0)
    return false
  return true
}

// Positive Hyprland ids are real workstations. Special ids use the monitor's
// current workstation instead. Never return a special-workspace name.
function displayWorkspaceId(row) {
  if (!row)
    return 0
  var n = Number(row.workspaceId)
  if (n > 0)
    return n
  var mon = Number(row.monitorWorkspaceId)
  if (mon > 0)
    return mon
  if (String(row.workspace || "").indexOf("special:") === 0)
    return 0
  var named = Number(row.workspace)
  if (named > 0)
    return named
  return 0
}

function rowWorkspaceLabel(row, slots) {
  var n = displayWorkspaceId(row)
  if (n > 0)
    return pageLabel(n, slots)
  return ""
}

function pageForWorkspaceId(id, pageNames) {
  var n = Number(id)
  if (!(n > 0))
    return ""
  var key = String(n)
  if ((pageNames || []).indexOf(key) < 0)
    return ""
  return key
}

// Slots 1-9 of this monitor are always present. Slot 10 is added when it
// exists. Ids from another block are left out, or the strip would read
// 1-9 and then 1-3.
function pageNamesFor(block, slots, workspaces) {
  var base = block * slots
  var highest = 9
  var list = workspaces || []
  var i
  for (i = 0; i < list.length; i++) {
    var ws = list[i]
    if (!ws || !isPagerWorkspace(workspaceName(ws), ws.id))
      continue
    var id = Number(ws.id)
    if (!(id > 0) || blockOf(id, slots) !== block)
      continue
    var slot = slotOf(id, slots)
    if (slot > highest)
      highest = slot
  }
  if (highest > slots)
    highest = slots
  var names = []
  for (i = 1; i <= highest; i++)
    names.push(String(base + i))
  return names
}

// Hyprland's movewindowv2 payload is address, workspace id, workspace name.
// The older movewindow payload is address, workspace name. A positive id is
// the workstation. A special workspace is not.
function movedWorkspaceId(parts) {
  if (!parts || parts.length < 2)
    return 0
  var id = Number(parts[1])
  if (id > 0)
    return id
  return 0
}

// Point one window at a new workstation in the grid's list. All reads this
// list, so the number can change while the grid stays open. The toplevel
// snapshot often still has the old workstation when the move event arrives.
function retargetWindow(rows, address, workspaceId) {
  var id = Number(workspaceId)
  var clean = String(address || "")
  var list = rows || []
  if (!clean || !(id > 0))
    return { rows: list, status: "ignored" }
  var next = []
  var status = "missing"
  var i
  var key
  for (i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row || row.address !== clean) {
      next.push(row)
      continue
    }
    if (Number(row.workspaceId) === id && String(row.workspace || "") === String(id)) {
      status = "same"
      next.push(row)
      continue
    }
    status = "updated"
    var moved = {}
    for (key in row) {
      if (Object.prototype.hasOwnProperty.call(row, key))
        moved[key] = row[key]
    }
    moved.workspace = String(id)
    moved.workspaceId = id
    next.push(moved)
  }
  if (status !== "updated")
    return { rows: list, status: status }
  return { rows: next, status: status }
}

// Windows that belong in one workspace's blurred background. Special
// workspaces are hidden while the grid is open, and a window on another
// monitor would be placed against the wrong screen. A zero size has no place.
function backdropWindows(rows, workspaceId, monitorId) {
  var want = Number(workspaceId)
  var mon = Number(monitorId)
  var list = rows || []
  var out = []
  var i
  if (!(want > 0))
    return out
  for (i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row)
      continue
    if (!(Number(row.workspaceId) > 0))
      continue
    if (String(row.workspace || "").indexOf("special:") === 0)
      continue
    if (Number(row.workspaceId) !== want)
      continue
    if (mon >= 0 && Number(row.monitorId) !== mon)
      continue
    if (!(Number(row.bw) > 0) || !(Number(row.bh) > 0))
      continue
    out.push(row)
  }
  return out
}

// Place those windows in the overlay's coordinate space. bx/by/bw/bh are
// Hyprland layout pixels relative to the monitor. scaleX/scaleY map them
// onto the screen the grid is covering.
function placeBackdrop(rows, workspaceId, monitorId, scaleX, scaleY) {
  var sx = Number(scaleX)
  var sy = Number(scaleY)
  if (!(sx > 0))
    sx = 1
  if (!(sy > 0))
    sy = 1
  var picked = backdropWindows(rows, workspaceId, monitorId)
  var out = []
  var i
  for (i = 0; i < picked.length; i++) {
    var row = picked[i]
    out.push({
      address: row.address,
      px: Number(row.bx) * sx,
      py: Number(row.by) * sy,
      pw: Number(row.bw) * sx,
      ph: Number(row.bh) * sy
    })
  }
  return out
}

function prettyApp(app, title) {
  var text = String(app || "")
  var slash = text.lastIndexOf("/")
  if (slash >= 0)
    text = text.slice(slash + 1)
  var dot = text.lastIndexOf(".")
  if (dot >= 0 && dot < text.length - 1)
    text = text.slice(dot + 1)
  var label = text || "Window"
  // Grok Build's window class is the terminal it runs in, and the quake
  // console's class is org.omarchy.agent. A grok title should not read as
  // a plain terminal.
  var kind = label.toLowerCase()
  var titled = String(title || "").toLowerCase()
  if (titled.indexOf("grok") !== -1 && (kind === "foot" || kind === "agent" || kind === "kitty" || kind === "alacritty" || kind === "ghostty" || kind === "wezterm"))
    return "grok"
  return label
}
