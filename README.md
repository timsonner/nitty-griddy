# NittyGriddy

Window grid overview for Omarchy. It shows every open window on the focused screen. Three-finger swipes open and dismiss it after you copy the gesture snippet.

## What the plugin does

Enabling the plugin installs the overlay. It does not change your Hyprland swipes or keys.

- The grid opens on the focused screen, on All, and lists open windows. Live thumbnails appear when Hyprland can export them.
- The strip keeps this monitor's workspaces 1 through 9 even when empty. Slot 10 is added when that workspace exists. A card shows that same number, so a window Hyprland numbers 14 reads as workspace 4.
- Click a card to focus that window. Click the × to close it. Click the empty backdrop to dismiss the grid.
- Arrow keys move the selection. Enter focuses the selected window. Typing filters by title, app, or workspace.
- Middle-click and Shift+Q do not close a card. Super+Q is not changed. It still closes the focused window, including while the grid is open.
- While the grid is open the pointer stays where it is, and a visible quake console is hidden. Dismissing the grid brings that console back.

## What you set up

Copy `gestures.snippet.lua` and `bindings.snippet.lua` into `~/.config/hypr/`, then reload Hyprland and restart the shell. The steps are under Swipes and shortcuts. Until you do that, three-finger swipes stay as they are, and Escape, Super+W, and Super+Shift+number keep Omarchy's behavior. The grid will not see them.

After the snippets are in place:

- Three-finger up opens the grid. Down dismisses it. Left and right switch workspaces while the grid is closed, and page the strip while it is open. The desktop workspace stays put during that paging.
- Escape dismisses the grid only while it is open.
- Super+W closes the selected card while the grid is open, and still closes the focused window when the grid is closed.
- Super+Shift+1 through Super+Shift+9, and Super+Shift+0 for workspace 10, move the selected card while the grid is open and follow it. With the grid closed, the same chords still move the focused window.

The plugin does not bind Super+A. Omarchy uses that chord for Select all.

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

## Swipes and shortcuts

These swipes and keys are yours to install. The pointer actions further down are part of the overlay and need no extra bind.

Copy `gestures.snippet.lua` to `~/.config/hypr/gestures.lua`. Copy `bindings.snippet.lua` into `~/.config/hypr/bindings.lua`. `~/.config/hypr/hyprland.lua` does not load `gestures.lua` unless you require it. Add that require after `require("default.hypr.omarchy")`:

```lua
require("default.hypr.omarchy")

require("hypr.gestures")
```

Stock Omarchy does not register three-finger gestures, so do not unset them. `action = "unset"` on a gesture nothing registered is a config error. Hyprland keeps the first gesture for a fingers-and-direction pair, so this file should be the only three-finger set in the user config.

Do not add `omarchy_default_gestures = false` yourself. If an update inserts that line because it saw `hl.gesture` in `~/.config/hypr`, leave it. This file binds all four directions, so the swipes still work. Deleting the line lets later Omarchy defaults register first, and these binds will not replace them.

```sh
hyprctl reload
omarchy restart shell
```

`hyprctl reload` picks up the gestures and the keys. `omarchy restart shell` mounts the overlay. Later QML edits hot-reload when you save the plugin. A gesture or key change still needs `hyprctl reload`.

### Trackpad

Three fingers. The grid opens on All: every window, including ones on a special workspace. No card is selected.

| Swipe | Grid closed | Grid open |
|---|---|---|
| Up | Opens the grid | Opens the grid. It does not toggle closed |
| Down | Does nothing. It does not open the menu or a console | Dismisses the grid. Focus returns to the window that was focused, if it is still open. A quake console that was showing comes back |
| Right | Next workspace, including an empty one | Next page. All, then this monitor's workspaces. 1 through 9 stay even when empty. Slot 10 is added when that workspace exists. The desktop workspace stays put |
| Left | Previous workspace, including an empty one | Previous page, back toward All. The desktop workspace stays put |

`hl.dsp.event` posts `custom>>timsonner.nitty-griddy:open` or `custom>>timsonner.nitty-griddy:close` on Hyprland’s socket2. The overlay is `keepLoaded`, so the shell mounts it at startup and it hears those events.

### Keys

| Key | Grid closed | Grid open |
|---|---|---|
| Escape | Passes through to the focused app | Dismisses the grid. The compositor bind runs before an input method, so this still works while fcitx5 is running |
| Super+W | Closes the focused window | Closes the selected card. The grid stays if other windows remain. Hover a card, or move to it with the arrow keys, first. With nothing selected, this does not close the window behind the grid |
| Super+Q | Closes the focused window. The snippet does not change this chord | Still closes the focused window, not the card |
| Super+Shift+1 through Super+Shift+9, and Super+Shift+0 | Moves the focused window to that workspace. 0 is workspace 10, same as the bar | Moves the selected card there and follows it. Hover a card, or move to it with the arrow keys, first. With nothing selected, this does not move the window behind the grid |
| Arrow keys | Unchanged | Move the selection |
| Enter | Unchanged | Focuses the selected window and dismisses the grid. The pointer stays where it is |
| Type, Backspace | Unchanged | Filters by title, app, or workspace. A letter does not close a window |

The plugin does not bind Super+A. Omarchy uses that chord for Select all. Open the grid with a three-finger swipe up.

### Pointer

| Action | Result |
|---|---|
| Click a card | Focuses that window and dismisses the grid. The previously focused window is not restored. The pointer stays where it is |
| × on a card | Closes that window. The grid stays if others remain |
| Click the empty backdrop | Dismisses the grid, same as swipe down or Escape |

Middle-click and Shift+Q do not close a card.

The hint along the bottom reads: Type to filter · Arrow keys to move · Enter to focus · Super+W to close · Esc to dismiss · Swipe for workspace. The strip under the title shows All, then each workspace. The current page is the accent color. The grid is on the focused screen. Thumbnails are live while the grid is open. Until a frame arrives, the card shows the app and the title. Window titles are plain text.

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

Remove the NittyGriddy gestures from `~/.config/hypr/gestures.lua`, and remove `require("hypr.gestures")` if this plugin was the only reason it was there. In `~/.config/hypr/bindings.lua`, remove the Escape dismiss bind, the Super+W rebind, and the Super+Shift+number rebinds. Deleting that rebind gives Super+W back to Omarchy’s close-window bind. Then:

```sh
omarchy plugin remove timsonner.nitty-griddy --yes
hyprctl reload
omarchy restart shell
```

Removing the plugin does not restore the swipes by itself, because those lines live in your config.

## About the name

NittyGriddy takes its name from the Nitty Gritty Dirt Band.

## Credits

MIT license. The bounded client list and the short pause before focus follow ideas in [kristofferR/omarchy-expose](https://github.com/kristofferR/omarchy-expose) and [harel/omarchy-birdseye](https://github.com/harel/omarchy-birdseye), both MIT. This overlay is a separate implementation.
