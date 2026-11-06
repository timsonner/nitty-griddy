# NittyGriddy

Window grid overview for Omarchy — three-finger up opens every window, down dismisses.

## Requirements

- Omarchy Quattro with shell plugins
- Hyprland Lua config (`hl.gesture`, `hl.dsp`)
- `jq`
- `hyprctl`

Quickshell ships with Omarchy. Live thumbnails need Hyprland toplevel export. Without it, each card still shows the app name and the window title.

## Install

```sh
omarchy plugin add https://github.com/timsonner/nitty-griddy --enable --yes
```

That clones the plugin to `~/.config/omarchy/plugins/tim.nitty-griddy/`. Plugin id: `tim.nitty-griddy`.

## Gestures

Omarchy already binds three-finger up and three-finger down. Hyprland rejects a second gesture on the same fingers and direction, so unset those two, then bind NittyGriddy. Leave three-finger left and right alone. They keep switching workspaces.

Do not set `omarchy_default_gestures = false`. That also removes the left and right swipes. If an update inserted that line because it saw `hl.gesture(` in `~/.config/hypr`, delete the line. The unsets below are enough.

`~/.config/hypr/hyprland.lua` does not load `gestures.lua` unless you require it. Add the require **after** `require("default.hypr.omarchy")`, so the unsets run after Omarchy’s defaults exist:

```lua
require("default.hypr.omarchy")

require("hypr.gestures")
```

Paste `gestures.snippet.lua` into `~/.config/hypr/gestures.lua`. It is the only three-finger up and down pair you want in the user config:

```lua
hl.gesture({ fingers = 3, direction = "up", action = "unset" })
hl.gesture({ fingers = 3, direction = "down", action = "unset" })

hl.gesture({
  fingers = 3,
  direction = "up",
  action = function()
    hl.dispatch(hl.dsp.event("tim.nitty-griddy:open"))
  end,
})

hl.gesture({
  fingers = 3,
  direction = "down",
  action = function()
    hl.dispatch(hl.dsp.event("tim.nitty-griddy:close"))
  end,
})
```

Up only opens. Down only dismisses. Down does nothing when the grid is already closed, and it does not bring back the console or the menu.

`hl.dsp.event` posts `custom>>tim.nitty-griddy:open` or `custom>>tim.nitty-griddy:close` on Hyprland’s socket2. The overlay is `keepLoaded`, so the shell mounts it at startup and it hears those events.

## Keyboard

Optional. Paste `bindings.snippet.lua` into `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + A", "NittyGriddy", "omarchy-shell shell toggle tim.nitty-griddy '{}'")
```

`SUPER+A` toggles. The trackpad does not. Pick another chord if that one is already used.

## Reload

```sh
hyprctl reload
omarchy restart shell
```

`hyprctl reload` picks up the gestures and the key. `omarchy restart shell` mounts the overlay. Later QML edits hot-reload when you save the plugin. A gesture change still needs `hyprctl reload`.

## Controls

| Action | Result |
|---|---|
| Three-finger swipe up, or `omarchy-shell shell summon tim.nitty-griddy '{}'` | Grid opens with windows from all workspaces. No card is selected. The window that was focused is remembered and deselected |
| Three-finger swipe down, Esc, or a click on the empty backdrop | Grid dismisses and focus returns to that window if it is still open. Down is a no-op when it is already closed |
| Click a card, or Enter | Focus that window and dismiss the grid. The previously focused window is not restored |
| × on the card, middle-click, or Shift+Q | Close that window. The grid stays if others remain |
| Arrow keys | Move the selection |
| Type to filter | Narrow by title, app, or workspace. Backspace edits |

The hint along the bottom reads: Type to filter · Arrow keys to move · Enter to focus · Esc to dismiss. Typing a letter filters. It does not close a window.

The grid is on the focused screen. Thumbnails are live while the grid is open. Until a frame arrives, the card shows the app and the title. Window titles are plain text.

## IPC

```sh
omarchy-shell shell summon tim.nitty-griddy '{}'
omarchy-shell shell hide tim.nitty-griddy
omarchy-shell shell toggle tim.nitty-griddy '{}'
```

The plugin target is the same three calls:

```sh
omarchy-shell tim.nitty-griddy open
omarchy-shell tim.nitty-griddy close
omarchy-shell tim.nitty-griddy toggle
```

Socket2 events, which is what the gestures dispatch:

```sh
hyprctl dispatch 'hl.dsp.event("tim.nitty-griddy:open")'
hyprctl dispatch 'hl.dsp.event("tim.nitty-griddy:close")'
hyprctl dispatch 'hl.dsp.event("tim.nitty-griddy:toggle")'
```

## Validate

```sh
omarchy plugin validate ~/.config/omarchy/plugins/tim.nitty-griddy
```

In a checkout of this repo, `./validate` checks the manifest and the helpers without a running shell.

## Troubleshooting

**`hyprctl configerrors` mentions a duplicate gesture.** Up or down is bound twice. Keep a single unset, then a single bind, for each direction.

**Swipe does nothing after a shell restart.** The shell is not seeing the socket2 event. In the gesture functions, replace the `hl.dispatch(hl.dsp.event(...))` lines with summon and hide. Use `hl.dispatch(hl.dsp.exec_cmd(...))`. A bare `hl.dsp.exec_cmd()` only builds a dispatcher and does not run. `exec_cmd` goes through a shell, which is what the `'{}'` payload needs.

```lua
hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon tim.nitty-griddy '{}'"))
hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide tim.nitty-griddy"))
```

**No thumbnails.** The cards still show the app name and the title. Check that Hyprland offers toplevel export and that nothing is blocking screen capture for Quickshell.

**Plugin not listed.** Run `omarchy plugin validate` on the plugin directory, then `omarchy-shell shell rescanPlugins`, then `omarchy plugin enable tim.nitty-griddy --yes`.

## Uninstall

Remove the NittyGriddy block from `~/.config/hypr/gestures.lua` and the `SUPER+A` line from `~/.config/hypr/bindings.lua`. Remove `require("hypr.gestures")` if this plugin was the only reason it was there. Then:

```sh
omarchy plugin remove tim.nitty-griddy --yes
hyprctl reload
omarchy restart shell
```

After the unsets are gone, reload brings back Omarchy’s default three-finger up and down gestures. Removing the plugin does not restore them by itself, because those lines live in your config.

## About the name

NittyGriddy takes its name from the Nitty Gritty Dirt Band.

## Credits

MIT license. The bounded client list and the short pause before focus follow ideas in [kristofferR/omarchy-expose](https://github.com/kristofferR/omarchy-expose) and [harel/omarchy-birdseye](https://github.com/harel/omarchy-birdseye), both MIT. This overlay is a separate implementation.
