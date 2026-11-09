// Direct checks of the workspace-number rules. No timers.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const source = readFileSync(join(root, "workspace-label.js"), "utf8")
const labels = runInNewContext(source + "\n({ slotOf, blockOf, pageLabel, workspaceIdForSlot, workspaceName, isPagerWorkspace, displayWorkspaceId, rowWorkspaceLabel, pageForWorkspaceId, pageNamesFor, movedWorkspaceId, retargetWindow, backdropWindows, placeBackdrop, prettyApp })\n", {})

const slots = 10
const left = 1

function check(name, actual, expected) {
  assert.equal(JSON.stringify(actual), JSON.stringify(expected), name)
}

check("id 14 is slot 4", labels.pageLabel(14, slots), "4")
check("id 11 is slot 1", labels.pageLabel(11, slots), "1")
check("id 21 is slot 1 on the next monitor", labels.pageLabel(21, slots), "1")
check("id 20 is slot 10", labels.pageLabel(20, slots), "10")
check("special id has no slot label", labels.pageLabel(-98, slots), "")
check("slot 4 on the left monitor is id 14", labels.workspaceIdForSlot(4, left, slots), 14)
check("slot 1 on the left monitor is id 11", labels.workspaceIdForSlot(1, left, slots), 11)
check("slot 0 is not a workstation", labels.workspaceIdForSlot(0, left, slots), 0)
check("slot 11 is not a workstation", labels.workspaceIdForSlot(11, left, slots), 0)

const chrome = { workspaceId: 11, workspace: "11", title: "GitHub - nitty-griddy overview ".repeat(8) }
check("chrome keeps its workstation", labels.displayWorkspaceId(chrome), 11)
check("a long chrome title still labels slot 1", labels.rowWorkspaceLabel(chrome, slots), "1")

const quake = { workspaceId: -98, workspace: "special:qconsole", monitorWorkspaceId: 12 }
check("quake uses the screen's workstation", labels.displayWorkspaceId(quake), 12)
check("quake is labeled 2, not its special name", labels.rowWorkspaceLabel(quake, slots), "2")
check("quake is not a strip workspace", labels.isPagerWorkspace("special:qconsole", -98), false)

const namedOnly = { workspaceId: 0, workspace: "13" }
check("a numeric workspace name is used when the id is missing", labels.displayWorkspaceId(namedOnly), 13)

const pages = labels.pageNamesFor(left, slots, [
  { id: 1, name: "1" },
  { id: 2, name: "2" },
  { id: 3, name: "3" },
  { id: 11, name: "11" },
  { id: 14, name: "14" },
  { id: 15, name: "15" },
  { id: 21, name: "21" },
  { id: -98, name: "special:qconsole" }
])
check("left strip is 11 through 19, without guests or the other monitor", pages, ["11", "12", "13", "14", "15", "16", "17", "18", "19"])
check("clicking 14 pages to that id", labels.pageForWorkspaceId(14, pages), "14")
check("a guest id is not a page on this strip", labels.pageForWorkspaceId(1, pages), "")
check("the other monitor's id is not a page here", labels.pageForWorkspaceId(21, pages), "")

const withTen = labels.pageNamesFor(left, slots, [{ id: 20, name: "20" }])
check("slot 10 is added only when that workspace exists", withTen, ["11", "12", "13", "14", "15", "16", "17", "18", "19", "20"])

check("chrome stays chrome", labels.prettyApp("google-chrome", "GitHub - grok"), "google-chrome")
check("a grok session in foot is grok", labels.prettyApp("foot", "Clickable workstation IDs - grok"), "grok")
check("the quake console running grok is grok", labels.prettyApp("org.omarchy.agent", "session - grok"), "grok")
check("a plain terminal stays a terminal", labels.prettyApp("foot", "tim@XPS15-OMARCHY:~"), "foot")
check("obs uses the class tail", labels.prettyApp("com.obsproject.Studio", "OBS"), "Studio")

check("movewindowv2 carries the workstation id", labels.movedWorkspaceId(["0xaaa", "14", "14"]), 14)
check("a workspace name is not an id", labels.movedWorkspaceId(["0xaaa", "special:qconsole"]), 0)
check("a short move payload has no workstation", labels.movedWorkspaceId(["0xaaa"]), 0)

const grid = [
  { address: "0xaaa", title: "GitHub", app: "google-chrome", appLabel: "google-chrome", workspace: "11", workspaceId: 11, monitorWorkspaceId: 12, activated: true },
  { address: "0xbbb", title: "notes", app: "foot", appLabel: "foot", workspace: "12", workspaceId: 12, monitorWorkspaceId: 12, activated: false }
]
const moved = labels.retargetWindow(grid, "0xaaa", 14)
check("sending chrome to id 14 updates All", moved.status, "updated")
check("the moved card is workstation 14", labels.displayWorkspaceId(moved.rows[0]), 14)
check("All labels the moved card as 4", labels.rowWorkspaceLabel(moved.rows[0], slots), "4")
check("the other card stays put", moved.rows[1], grid[1])
const again = labels.retargetWindow(moved.rows, "0xaaa", 14)
check("a second report of the same move is unchanged", again.status, "same")
check("a move keeps the window's place on screen", labels.retargetWindow([
  { address: "0xaaa", workspace: "11", workspaceId: 11, bx: 12, by: 20, bw: 400, bh: 300, monitorId: 1 }
], "0xaaa", 14).rows[0].bw, 400)
check("an unknown window is left for a full refresh", labels.retargetWindow(grid, "0xccc", 14).status, "missing")
check("a special id is not a workstation move", labels.retargetWindow(grid, "0xaaa", -98).status, "ignored")

const scene = [
  { address: "0xaaa", workspace: "14", workspaceId: 14, monitorId: 1, bx: 10, by: 20, bw: 400, bh: 300 },
  { address: "0xbbb", workspace: "11", workspaceId: 11, monitorId: 1, bx: 0, by: 0, bw: 200, bh: 100 },
  { address: "0xccc", workspace: "special:qconsole", workspaceId: -98, monitorId: 1, bx: 0, by: 0, bw: 800, bh: 400 },
  { address: "0xddd", workspace: "14", workspaceId: 14, monitorId: 2, bx: 0, by: 0, bw: 500, bh: 500 },
  { address: "0xeee", workspace: "14", workspaceId: 14, monitorId: 1, bx: 0, by: 0, bw: 0, bh: 100 }
]
check("workspace 14 on this screen is one window", labels.backdropWindows(scene, 14, 1).map((row) => row.address), ["0xaaa"])
check("the placed window follows the screen scale", labels.placeBackdrop(scene, 14, 1, 2, 2), [
  { address: "0xaaa", px: 20, py: 40, pw: 800, ph: 600 }
])
check("an empty workspace has no backdrop windows", labels.placeBackdrop(scene, 15, 1, 1, 1), [])

console.log("workspace-label: ok")
