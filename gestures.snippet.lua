-- NittyGriddy (tim.nitty-griddy)
--
-- Drop this into ~/.config/hypr/gestures.lua.
-- Stock Omarchy does not load that file. In ~/.config/hypr/hyprland.lua,
-- AFTER require("default.hypr.omarchy"), add this once if it is not already there:
--
--   require("hypr.gestures")
--
-- The require has to run after Omarchy's defaults. An earlier require unsets
-- gestures that have not been registered yet, and the defaults then win.
--
-- Only three-finger up and down are replaced. Do not set
-- omarchy_default_gestures = false — that also removes three-finger
-- left/right workspace swipes.
--
-- Up opens. Down dismisses. Down does nothing when the overview is already
-- closed: it does not bring back the quake console or the Omarchy menu.
-- Hyprland will not accept a second gesture on the same fingers and direction,
-- so this file should be the only up/down pair in the user config.

hl.gesture({ fingers = 3, direction = "up", action = "unset" })
hl.gesture({ fingers = 3, direction = "down", action = "unset" })

hl.gesture({
  fingers = 3,
  direction = "up",
  action = function()
    -- Explicit open. hl.dsp.event posts custom>>tim.nitty-griddy:open on socket2.
    -- The keepLoaded overlay listens for that. It never toggles closed.
    hl.dispatch(hl.dsp.event("tim.nitty-griddy:open"))
  end,
})

hl.gesture({
  fingers = 3,
  direction = "down",
  action = function()
    -- Explicit dismiss. A no-op when the overview is already closed.
    hl.dispatch(hl.dsp.event("tim.nitty-griddy:close"))
  end,
})

-- If a swipe does nothing after `omarchy restart shell`, the shell is not
-- seeing socket2 custom events. Replace the two hl.dispatch lines above with
-- the official summon/hide IPC (also explicit open and close, not toggle):
--
--   hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon tim.nitty-griddy '{}'"))
--   hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide tim.nitty-griddy"))
--
-- Use exec_cmd, not a bare hl.dsp.exec_cmd() call. The bare call only builds
-- a dispatcher. hl.dispatch runs it, and exec_cmd goes through a shell so the
-- '{}' payload stays one argument. exec_raw does not.
