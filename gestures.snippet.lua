-- NittyGriddy (timsonner.nitty-griddy)
--
-- Drop this into ~/.config/hypr/gestures.lua.
-- Stock Omarchy does not load that file. In ~/.config/hypr/hyprland.lua,
-- AFTER require("default.hypr.omarchy"), add this once if it is not already there:
--
--   require("hypr.gestures")
--
-- The require has to run after Omarchy's defaults.
--
-- Omarchy 4.0 registers no three-finger gestures. Omarchy 4.5 and edge
-- register all four (left/right switch workspace, up opens the AI console,
-- down opens the Omarchy menu), and Hyprland keeps the first gesture for a
-- fingers-and-direction pair. So the block below unsets Omarchy's four only
-- when Omarchy actually loaded them. On 4.0, or when
-- omarchy_default_gestures = false is set, nothing is unset, because
-- action = "unset" on a missing gesture is a config error.
-- Omarchy's four-finger gestures are left alone.
--
-- Do not add omarchy_default_gestures = false yourself. If an Omarchy
-- migration added it because it saw hl.gesture here, leave it.
--
-- Up opens. Down dismisses. Down does nothing when the overview is already
-- closed: it does not bring back the quake console or the Omarchy menu.
-- Hyprland will not accept a second gesture on the same fingers and direction,
-- so this file should be the only up/down pair in the user config.

if package.loaded["default.hypr.gestures"] then
  for _, direction in ipairs({ "up", "down", "left", "right" }) do
    hl.gesture({ fingers = 3, direction = direction, action = "unset" })
  end
end

hl.gesture({
  fingers = 3,
  direction = "up",
  action = function()
    -- Explicit open. hl.dsp.event posts custom>>timsonner.nitty-griddy:open on socket2.
    -- The keepLoaded overlay listens for that. It never toggles closed.
    hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:open"))
  end,
})

hl.gesture({
  fingers = 3,
  direction = "down",
  action = function()
    -- Explicit dismiss. A no-op when the overview is already closed.
    hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:close"))
  end,
})

-- While the grid is open, left and right page its workspace filter.
-- All is the leftmost page, then workspace 1, 2, 3, and so on.
-- Right walks forward. Left walks back toward All. The desktop workspace
-- stays put. All and an empty workstation show the blurred wallpaper.
-- A workstation with windows shows those windows. When the grid is closed,
-- the same swipes still move workspace.
local function nitty_griddy_mapped()
  local layers = hl.get_layers({ namespace = "timsonner-nitty-griddy" })
  return layers ~= nil and #layers > 0
end

hl.gesture({
  fingers = 3,
  direction = "left",
  action = function()
    if nitty_griddy_mapped() then
      hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:workspace-prev"))
      return
    end
    hl.dispatch(hl.dsp.focus({ workspace = "r-1" }))
  end,
})

hl.gesture({
  fingers = 3,
  direction = "right",
  action = function()
    if nitty_griddy_mapped() then
      hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:workspace-next"))
      return
    end
    hl.dispatch(hl.dsp.focus({ workspace = "r+1" }))
  end,
})

-- If a swipe does nothing after `omarchy restart shell`, the shell is not
-- seeing socket2 custom events. Replace the two hl.dispatch lines above with
-- the official summon/hide IPC (also explicit open and close, not toggle):
--
--   hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon timsonner.nitty-griddy '{}'"))
--   hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide timsonner.nitty-griddy"))
--
-- Use exec_cmd, not a bare hl.dsp.exec_cmd() call. The bare call only builds
-- a dispatcher. hl.dispatch runs it, and exec_cmd goes through a shell so the
-- '{}' payload stays one argument. exec_raw does not.
