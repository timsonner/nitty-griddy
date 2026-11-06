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
-- Stock Omarchy does not register three-finger up or down, so there is
-- nothing to unset. action = "unset" on a missing gesture is a config error
-- ("Can't remove a non-existent gesture") on lines that used to do that.
-- Do not set omarchy_default_gestures = false — that also removes three-finger
-- left/right workspace swipes when those defaults exist.
--
-- Up opens. Down dismisses. Down does nothing when the overview is already
-- closed: it does not bring back the quake console or the Omarchy menu.
-- Hyprland will not accept a second gesture on the same fingers and direction,
-- so this file should be the only up/down pair in the user config.

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
-- stays put. When the grid is closed, the same swipes still move workspace.
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
