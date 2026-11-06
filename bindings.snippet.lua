-- NittyGriddy (timsonner.nitty-griddy)
--
-- Drop this into ~/.config/hypr/bindings.lua (that file is already loaded).
-- Do not bind SUPER + A. Omarchy uses it for Select all.
-- Three-finger swipe up opens the grid and swipe down closes it.
-- These binds are Escape, and Super+W while the grid is open.

-- fcitx5's input-method grab sits in front of the overlay, so the grid never
-- sees Escape. Hyprland runs this bind first. Consume the key only while the
-- grid is mapped, and let it through to fcitx and the focused app otherwise.
-- Leave omarchy-fcitx5.service enabled. Caps Lock compose sequences need it.
local function nitty_griddy_mapped()
  local layers = hl.get_layers({ namespace = "timsonner-nitty-griddy" })
  return layers ~= nil and #layers > 0
end

local function dismiss_nitty_griddy()
  if not nitty_griddy_mapped() then
    return { ok = false }
  end
  hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide timsonner.nitty-griddy"))
end

o.bind_commands[dismiss_nitty_griddy] = "omarchy-shell shell hide timsonner.nitty-griddy"
o.bind("ESCAPE", "NittyGriddy dismiss", dismiss_nitty_griddy, { auto_consuming = true })

-- Super+W closes the focused window on the desktop. While the grid is open
-- the same chord closes the selected card instead, and does not close the
-- window behind the grid. Super+Q keeps the desktop close.
local function close_nitty_or_window()
  if nitty_griddy_mapped() then
    hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:close-selected"))
    return
  end
  hl.dispatch(hl.dsp.window.close())
end

o.bind_commands[close_nitty_or_window] = "hl.dsp.window.close()"
o.rebind("SUPER + W", "Close window", close_nitty_or_window)
