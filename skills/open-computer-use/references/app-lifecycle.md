# App Lifecycle Recipes

Read this when a task requires quitting, relaunching, or activating a GUI app
before operating it.

On macOS, `ocu app` provides the primary lifecycle surface. It uses
LaunchServices to check whether the app is running and AppleScript for
activation and graceful quit.

## Status

```sh
ocu app status dev.zcode.app
ocu app status dev.zcode.app --json
```

The JSON form returns `{ "bundleId", "action": "status", "running", "pid" }`.

## Launch and verify

```sh
ocu app launch dev.zcode.app
ocu app status dev.zcode.app
ocu app activate dev.zcode.app
```

`launch` waits up to the timeout (default 10 seconds) for the process to appear.
`activate` brings a running app forward without clicking its window. After either
command, read the window state before acting:

```sh
ocu call get_app_state --args '{"app":"ZCode"}' --no-screenshot
```

A newly launched app may restore its previous session, show a welcome sheet, or
open a different window. Always observe again; do not reuse window or element
indexes from before the relaunch.

## Quit gracefully

```sh
ocu app quit dev.zcode.app
ocu app quit dev.zcode.app --timeout 5
```

`quit` sends the app's normal quit request and waits for the process to exit. It
does not click through unsaved-changes dialogs. If the app is still running after
the timeout, the command reports the remaining pid and exits non-zero. Read the
dialog with `get_app_state`, report it to the user, and wait for a decision.

## Manual fallback

If `ocu app` is unavailable, use the bundle identifier directly:

```sh
osascript -e 'tell application id "com.example.App" to quit'
osascript -e 'tell application id "com.example.App" to activate'
open -b com.example.App
lsappinfo info -only pid -app com.example.App
```

`lsappinfo` prints `"pid"=<number>` while the app is running and nothing after it
exits. This avoids depending on a localized display name.

## Generic rules

- Prefer the bundle identifier over the display name; names are localized.
- `open -b` reuses a running instance instead of starting a second one.
- Do not force-kill a process unless the user explicitly asks; a force-kill can
  lose unsaved work and leaves the app in a different restore state.
- After relaunch, verify both the process and the visible window. A running
  process with no window is not ready for GUI automation.
