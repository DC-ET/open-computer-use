# App Lifecycle Recipes

Read this when a task requires quitting, relaunching, or activating a GUI app
before operating it.

`ocu` does not yet expose a native `app quit` command. Use the app's bundle
identifier with AppleScript, then verify the process actually exited.

## Quit gracefully

```sh
osascript -e 'tell application id "com.example.App" to quit'
```

Wait for the process to disappear instead of assuming the quit completed:

```sh
for i in $(seq 1 15); do
  if ! pgrep -x "AppName" >/dev/null; then echo "exited"; break; fi
  sleep 1
done
```

If the app shows an unsaved-changes sheet, do not click "Don't Save"
automatically. Read the dialog with `get_app_state`, report it to the user, and
wait for a decision. A graceful quit that remains blocked is a user decision,
not a failed automation step.

## Relaunch and verify

```sh
open -b com.example.App
sleep 2
osascript -e 'tell application id "com.example.App" to activate'
ocu call list_apps | jq -r '.content[]?.text' | grep 'com.example.App'
```

Then read the window state before acting:

```sh
ocu call get_app_state --args '{"app":"AppName"}' --no-screenshot
```

A newly launched app may restore its previous session, show a welcome sheet, or
open a different window. Always observe again; do not reuse window or element
indexes from before the relaunch.

## Generic rules

- Prefer the bundle identifier over the display name; names are localized.
- `open -b` reuses a running instance instead of starting a second one.
- `osascript activate` brings the app forward without clicking its window.
- Do not force-kill a process unless the user explicitly asks; a force-kill can
  lose unsaved work and leaves the app in a different restore state.
- After relaunch, verify both the process and the visible window. A running
  process with no window is not ready for GUI automation.
