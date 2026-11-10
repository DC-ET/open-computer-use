# Text Input Troubleshooting

Read this when `type_text` returns success but the target field does not change,
when `set_value` cannot verify a value, or when a web/Electron control ignores
accessibility writes.

## 1. Confirm the target is focused

A click can succeed without moving focus. Read the focused element before
typing:

```sh
ocu call get_app_state --args '{"app":"Your App","include_screenshot":false}' \
  | jq -r '.content[] | select(.type=="text") | .text' | grep 'focused UI element'
```

With the JS API:

```sh
ocu js --quiet '
var app = await cua.getApp("Your App", { initialState: false });
var q = await app.query({ role: "AXTextArea", limit: 10 });
nodeRepl.write(JSON.stringify(q.matches));
'
```

If the focused element is not the text control, click it first. Prefer
`element_index` from a fresh snapshot. If the control is covered or in another
Space, `click_method: "sky_click"` can focus a Chromium/Electron field without
raising the window.

## 2. Follow the input fallback ladder

For a focused editable control:

1. `type_text` with the default `keyMethod: "auto"`.
2. If the app ignores the AX write, the CLI now verifies the value and falls
   back to Unicode keyboard events (`CGEvent.keyboardSetUnicodeString`).
3. If auto still does nothing, retry with `keyMethod: "sky_key"` on macOS.
4. Use `set_value` only for native controls that expose a settable `AXValue`.
   It intentionally does not fall back to keyboard or clipboard input.
5. Last resort: paste. Back up the entire clipboard first and restore it
   afterwards (see below).

Example:

```sh
ocu js --quiet '
var app = await cua.getApp("ZCode", { initialState: false });
var q = await app.query({ role: "AXTextArea", limit: 10 });
if (q.matches.length !== 1) throw new Error("expected one text area");
await app.click(q.matches[0].index);
await app.typeText("你好", { keyMethod: "sky_key" });
'
```

## 3. Electron and Chromium controls

Electron/WebView text fields often accept `AXSelectedText` writes and still
leave the DOM unchanged. Do not trust a successful AX write. Verify one of:

- the `AXValue` read-back changed;
- the field's visible text changed in a screenshot;
- the app's own state (for example, the send button becomes enabled).

`press_key` usually reaches Electron even when `type_text` does not. If
`type_text` still fails, try:

```sh
ocu js --quiet '
var app = await cua.getApp("ZCode", { initialState: false });
await app.pressKey("cmd+a", { keyMethod: "sky_key" });
await app.pressKey("cmd+v", { keyMethod: "sky_key" });
'
```

## 4. Clipboard safety

`printf '你好' | pbcopy` can be decoded as MacRoman by Electron apps, producing
`‰Ω†Â•Ω`. Prefer:

```sh
osascript -e 'set the clipboard to "你好"'
```

The CLI does not currently provide a built-in paste tool. Before overwriting the
clipboard, save every pasteboard type, not just text. A clipboard can contain an
image, rich text, or multiple representations; `pbpaste > file` only preserves
plain text. If you cannot preserve all types, tell the user before overwriting.

Restore the clipboard after the paste, including on failure.

## 5. Verify, do not assume

`isError: false` means the call completed, not that the UI changed. After
typing, read the field value or take a screenshot. For a chat composer, also
verify that the send button became enabled before clicking it.

If the value is unchanged after both AX and keyboard paths, return a clear
failure instead of reporting success.
