# App Recipes

These are starting points, not hard-coded selectors. Always re-read the AX state
after navigation, app relaunch, or a failed action.

## ZCode / Electron chat composers

ZCode is an Electron app. Its composer is an `AXTextArea` inside an
`AXWebArea`, and an AX `AXSelectedText` write can return success without
changing the DOM.

```sh
osascript -e 'tell application id "dev.zcode.app" to activate'

ocu js --quiet '
var app = await cua.getApp("ZCode", { initialState: false });
var areas = await app.query({ role: "AXTextArea", limit: 10 });
if (areas.matches.length !== 1) throw new Error("expected one text area");
await app.click(areas.matches[0].index);
await app.typeText("你好", { keyMethod: "sky_key" });
var state = await app.getAXState({ includeScreenshot: false, emit: false });
nodeRepl.write(state);
'
```

To send, query the button by its label and click it:

```sh
ocu js --quiet '
var app = await cua.getApp("ZCode", { initialState: false });
var send = await app.query({ text: "发送", role: "AXButton", limit: 10 });
if (send.matches.length !== 1) throw new Error("send button not found");
await app.click(send.matches[0].index);
'
```

After sending, read the transcript with a large text limit:

```sh
ocu call get_app_state --args '{"app":"ZCode","text_limit":1000}' --no-screenshot
```

Prefer `sky_key` when auto typing does nothing. If the clipboard is used, set it
with `osascript -e 'set the clipboard to "..."'`; plain `pbcopy` text can be
decoded as MacRoman by Electron.

## Finder

Finder rows often expose their label on a child `AXStaticText`, so a
`query({ role: "AXRow", text: "..." })` can return zero matches while the row is
visible in the AX tree. Use the full state and the row's `element_index`:

```sh
ocu call get_app_state --args '{"app":"Finder"}' --no-screenshot
ocu call --calls '[
  {"tool":"get_app_state","args":{"app":"Finder","include_screenshot":false}},
  {"tool":"click","args":{"app":"Finder","element_index":"7"}}
]' --no-screenshot
```

Do not guess indexes across separate `ocu call` processes.

## TextEdit

TextEdit is a native AppKit text view. `set_value` works for many plain text
fields and preserves the caret; `type_text` is the safer choice when the field
must behave like real typing.

```sh
ocu call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit","include_screenshot":false}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"Hello"}}
]' --no-screenshot
```

## Google Chrome

Chrome exposes a large `AXWebArea`. Prefer text/role queries and element indexes
over pixel coordinates. For contenteditable fields, the input fallback ladder in
`input-troubleshooting.md` applies.

```sh
ocu js --quiet '
var app = await cua.getApp("Google Chrome", { initialState: false });
var q = await app.query({ text: "Search", role: "AXTextField", limit: 10 });
nodeRepl.write(JSON.stringify(q.matches));
'
```

If a window is covered or lives in another Space, `sky_click` / `sky_key` can
target it on macOS without raising it. Re-read the state after any navigation.
