# AGENTS.md

Instructions for AI agents that install, update, or remove NittyGriddy for a user, and for agents changing this repo. README.md has the full user-facing detail.

## Ground rules

- Enabling the plugin never touches Hyprland config. The swipes and keys come from two snippets that live in the user's `~/.config/hypr`. Copy or merge them only after the user agrees, and tell them what changes: on Omarchy 4.5 and edge, three-finger up stops opening the AI console and down stops opening the Omarchy menu. Escape, Super+W, Super+Q, Super+Tab, Super+Shift+Tab, and Super+Shift+number gain grid behavior while the grid is open.
- Back up any file in `~/.config/hypr` before you edit it.
- Never use sudo. Never edit `/usr/share/omarchy` or anything under `$OMARCHY_PATH`.
- Do not add `omarchy_default_gestures = false`. If an Omarchy migration already added it to `hyprland.lua`, leave it.
- Do not remove or unguard the `package.loaded["default.hypr.gestures"]` check in the gesture snippet. Unsetting a gesture Omarchy did not register is a config error on Omarchy 4.0, and skipping the unset breaks every swipe on 4.5.
- Do not bind Super+A. Omarchy uses it for Select all.

## Install

1. Add and enable the plugin:

   ```sh
   omarchy plugin add https://github.com/timsonner/nitty-griddy --enable --yes
   ```

2. Gestures. If `~/.config/hypr/gestures.lua` does not exist, copy `gestures.snippet.lua` there. If it exists, merge instead of overwriting. Keep the user's other gestures, and if any of them already uses three fingers up, down, left, or right, ask the user which one wins before you continue. Hyprland keeps only one gesture per fingers and direction.
3. Make sure `~/.config/hypr/hyprland.lua` has `require("hypr.gestures")` once, after `require("default.hypr.omarchy")`. Stock Omarchy does not load that file.
4. Keys. Append the non-comment contents of `bindings.snippet.lua` to `~/.config/hypr/bindings.lua`. Skip lines that are already there. If the user has their own binds on the same chords, ask first.
5. Reload and check:

   ```sh
   hyprctl reload
   hyprctl configerrors
   omarchy restart shell
   ```

   `hyprctl configerrors` must print nothing. "Previous UP shadows new UP" (or DOWN, LEFT, RIGHT) means an older copy of the gesture snippet is installed or another three-finger gesture comes first. Copy the current snippet again and reload.
6. Ask the user to swipe three fingers up and down to confirm the grid opens and closes.

## Update

```sh
omarchy plugin update timsonner.nitty-griddy
```

The update shows the user the diff and asks before it applies. It only refreshes the plugin folder. If `gestures.snippet.lua` or `bindings.snippet.lua` changed, offer to re-copy them, and then repeat the reload and the `hyprctl configerrors` check. After an Omarchy upgrade from 4.0 to 4.5, or from stable to edge, check `hyprctl configerrors` for gesture errors.

## Uninstall

Follow the Uninstall section of README.md. Remove only the NittyGriddy gestures and binds, and keep the user's own. Remove `require("hypr.gestures")` only if nothing else lives in that file. Then:

```sh
omarchy plugin remove timsonner.nitty-griddy --yes
hyprctl reload
omarchy restart shell
```

## Changing this repo

- Run `./validate` and `omarchy plugin validate .` before you commit. Both must pass.
- Commit subjects are one plain sentence ending in a period, matching `git log`.
- Bump `version` in `manifest.json` for user-visible changes, and keep `description` within the marketplace limit.
- The marketplace listing is pinned to an approved commit. After merging, file the "Verify and publish a newer upstream commit" form on omacom/omarchy-plugin-marketplace with the merged SHA.
