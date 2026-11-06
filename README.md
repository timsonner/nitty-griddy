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

That clones the plugin to `~/.config/omarchy/plugins/timsonner.nitty-griddy/`. Plugin id: `timsonner.nitty-griddy`.

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
    hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:open"))
  end,
})

hl.gesture({
  fingers = 3,
  direction = "down",
  action = function()
    hl.dispatch(hl.dsp.event("timsonner.nitty-griddy:close"))
  end,
})
```

Up only opens. Down only dismisses. Down does nothing when the grid is already closed, and it does not bring back the console or the menu.

The same file keeps three-finger left and right. With the grid closed they move to the previous and next workspace. With the grid open they page the cards instead: All is the leftmost page, then workspace 1, 2, 3, and so on. Right walks forward. Left walks back toward All. That swipe does not change the desktop workspace.

`hl.dsp.event` posts `custom>>timsonner.nitty-griddy:open` or `custom>>timsonner.nitty-griddy:close` on Hyprland’s socket2. The overlay is `keepLoaded`, so the shell mounts it at startup and it hears those events.

## Keyboard

Optional. Paste `bindings.snippet.lua` into `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + A", "NittyGriddy", "omarchy-shell shell toggle timsonner.nitty-griddy '{}'")
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
| Three-finger swipe up, or `omarchy-shell shell summon timsonner.nitty-griddy '{}'` | Grid opens on All, with windows from every workspace. No card is selected. The window that was focused is remembered and deselected |
| Three-finger swipe right while the grid is open | Next page. All, then workspace 1, 2, 3, and so on. The desktop workspace stays put |
| Three-finger swipe left while the grid is open | Previous page, back toward All |
| Three-finger swipe down, Esc, or a click on the empty backdrop | Grid dismisses and focus returns to that window if it is still open. A quake console that was showing comes back. Down is a no-op when it is already closed |
| Click a card, or Enter | Focus that window and dismiss the grid. The previously focused window is not restored. The pointer stays where it is |
| Super+W on a selected card | Close that window, the same chord as the desktop. The grid stays if others remain. Hover a card or move to it with the arrow keys first. With nothing selected, Super+W does not close the window behind the grid |
| × on the card | Close that window. The grid stays if others remain |
| Arrow keys | Move the selection |
| Type to filter | Narrow by title, app, or workspace. Backspace edits |

The hint along the bottom reads: Type to filter · Arrow keys to move · Enter to focus · Super+W to close · Esc to dismiss · Swipe for workspace. Typing a letter filters. It does not close a window. The workspace strip under the title shows All, then each workspace. The current page is the accent color.

The grid is on the focused screen. Thumbnails are live while the grid is open. Until a frame arrives, the card shows the app and the title. Window titles are plain text.

## IPC

```sh
omarchy-shell shell summon timsonner.nitty-griddy '{}'
omarchy-shell shell hide timsonner.nitty-griddy
omarchy-shell shell toggle timsonner.nitty-griddy '{}'
```

The plugin target is the same three calls:

```sh
omarchy-shell timsonner.nitty-griddy open
omarchy-shell timsonner.nitty-griddy close
omarchy-shell timsonner.nitty-griddy toggle
```

Socket2 events, which is what the gestures dispatch:

```sh
hyprctl dispatch 'hl.dsp.event("timsonner.nitty-griddy:open")'
hyprctl dispatch 'hl.dsp.event("timsonner.nitty-griddy:close")'
hyprctl dispatch 'hl.dsp.event("timsonner.nitty-griddy:toggle")'
hyprctl dispatch 'hl.dsp.event("timsonner.nitty-griddy:workspace-prev")'
hyprctl dispatch 'hl.dsp.event("timsonner.nitty-griddy:workspace-next")'
```

## Validate

```sh
omarchy plugin validate ~/.config/omarchy/plugins/timsonner.nitty-griddy
```

In a checkout of this repo, `./validate` checks the manifest and the helpers without a running shell.

## Troubleshooting

**`hyprctl configerrors` mentions a gesture.** Up or down is bound twice, or an unset names a gesture nothing registered. Keep one bind for each direction.

**Swipe does nothing after a shell restart.** The shell is not seeing the socket2 event. In the gesture functions, replace the `hl.dispatch(hl.dsp.event(...))` lines with summon and hide. Use `hl.dispatch(hl.dsp.exec_cmd(...))`. A bare `hl.dsp.exec_cmd()` only builds a dispatcher and does not run. `exec_cmd` goes through a shell, which is what the `'{}'` payload needs.

```lua
hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon timsonner.nitty-griddy '{}'"))
hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide timsonner.nitty-griddy"))
```

**Clicking a card does nothing, or the pointer sticks to one card.** The window that was focused stays selected under the grid, and Hyprland warps the pointer onto that window's real geometry. On this machine that window is often the quake console (`special:qconsole`). While the grid is open it sets `cursor:no_warps` and hides a visible special workspace. Dismissing restores both. Choosing another window leaves the console hidden.

**Escape does nothing while an input method is running.** fcitx5 can sit on the overlay's keyboard grab and swallow the key. `bindings.snippet.lua` binds Escape in the compositor and consumes it only while the grid is open, so the grid still dismisses. Leave `omarchy-fcitx5.service` enabled unless letters typed into the filter are swallowed too. Caps Lock compose sequences need that service.

**No thumbnails.** The cards still show the app name and the title. Check that Hyprland offers toplevel export and that nothing is blocking screen capture for Quickshell.

**Plugin not listed.** Run `omarchy plugin validate` on the plugin directory, then `omarchy-shell shell rescanPlugins`, then `omarchy plugin enable timsonner.nitty-griddy --yes`.

## Uninstall

Remove the NittyGriddy block from `~/.config/hypr/gestures.lua` and the `SUPER+A` line from `~/.config/hypr/bindings.lua`. Remove `require("hypr.gestures")` if this plugin was the only reason it was there. Then:

```sh
omarchy plugin remove timsonner.nitty-griddy --yes
hyprctl reload
omarchy restart shell
```

After the unsets are gone, reload brings back Omarchy’s default three-finger up and down gestures. Removing the plugin does not restore them by itself, because those lines live in your config.

## About the name

NittyGriddy takes its name from the Nitty Gritty Dirt Band.

## Credits

MIT license. The bounded client list and the short pause before focus follow ideas in [kristofferR/omarchy-expose](https://github.com/kristofferR/omarchy-expose) and [harel/omarchy-birdseye](https://github.com/harel/omarchy-birdseye), both MIT. This overlay is a separate implementation.
