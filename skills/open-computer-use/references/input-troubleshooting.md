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
   It now reports three outcomes instead of two: a readable value that matches
   verifies, a readable value that differs is an error naming what the control
   reports, and a control with no readable value at all returns success with a
   note. Treat that note as "unknown", not "done": read the state before
   retrying, because a second write could apply twice.
   Clearing a Chromium/Electron editor is the common case: the write works, but
   an empty contenteditable answers `"\n"` rather than `""`, so an empty request
   counts as verified when the control reports only whitespace.
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

A `cmd+v` chord can still do nothing in Electron: the event reaches the app but
the composer never reads the pasteboard. Do not retry it in a loop. If the field
is unchanged, go back to `type_text`, which writes the AX value and verifies it.

## 4. Clipboard safety

Passing non-ASCII text as a shell argument can reach the pasteboard already
mangled: `printf '你好' | pbcopy` can be decoded as MacRoman by Electron apps,
and `osascript -e 'set the clipboard to "你好"'` can turn every character into
`?`. Write the text to a UTF-8 file first, confirm it, then read the file:

```sh
pbcopy < /tmp/clip.txt
pbpaste | head -c 40
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
