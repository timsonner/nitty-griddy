-- NittyGriddy (tim.nitty-griddy)
--
-- Drop this into ~/.config/hypr/bindings.lua (that file is already loaded).
-- SUPER+A is free on a stock Omarchy install. Pick another chord if it is taken.
-- Avoid a modifier-only bind such as Super by itself.
--
-- This toggles. Trackpad swipe up/down stay explicit open and close in
-- gestures.snippet.lua. Toggle is only the keyboard fallback.

o.bind("SUPER + A", "NittyGriddy", "omarchy-shell shell toggle tim.nitty-griddy '{}'")

-- In-process equivalent, once the shell has loaded the plugin:
-- o.bind("SUPER + A", "NittyGriddy", hl.dsp.event("tim.nitty-griddy:toggle"))
