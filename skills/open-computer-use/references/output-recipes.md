# CLI Output Recipes

Read this when feeding Open Computer Use output to an agent or a script. The
default MCP-style JSON includes screenshots as base64; that is convenient for an
MCP host and wasteful for a terminal agent.

## Text-only state

Use `--no-screenshot` on `call` or `snapshot`:

```sh
ocu call get_app_state --args '{"app":"Finder"}' --no-screenshot
ocu snapshot --no-screenshot Finder
```

It is equivalent to `include_screenshot: false` / `--include-screenshot false`
and keeps AX state, focus, and element indexes. An explicit
`include_screenshot` in `--args` wins over the flag.

For a long tree, add a bigger budget and text limit:

```sh
ocu call get_app_state --args '{
  "app":"Google Chrome",
  "text_limit":1000,
  "max_tree_nodes":3000,
  "max_tree_depth":96
}' --no-screenshot
```

## Quiet JavaScript

`ocu js` prints the JavaScript API guidance once per process. Suppress it when
the output is consumed by another program:

```sh
ocu js --quiet '
var app = await cua.getApp("Finder", { initialState: false });
var q = await app.query({ role: "AXTextArea", limit: 10 });
nodeRepl.write(JSON.stringify(q.matches));
'
```

Combine with `--json` for a single machine-readable result:

```sh
ocu js --quiet --json '
var apps = await cua.listApps({ emit: false });
nodeRepl.write(apps);
'
```

## Write a screenshot directly

Use `--screenshot-out` when the image should be inspected as a file rather than
embedded in JSON:

```sh
ocu call get_app_state --args '{"app":"ZCode"}' --screenshot-out /tmp/zcode-state.png
ocu snapshot --screenshot-out /tmp/zcode-state.png ZCode
```

The output keeps the AX text and replaces the base64 image block with
`Screenshot written to <path>`. Additional images get `-1`, `-2`, ... before the
extension. `--screenshot-out` cannot be combined with `--no-screenshot`.

## Decode a screenshot manually

If the image is already in JSON and you need a file, decode it:

```sh
ocu call get_app_state --args '{"app":"ZCode"}' \
  | jq -r '.content[] | select(.mimeType=="image/png") | .data' \
  | base64 -d > /tmp/ocu-state.png
```

On a Retina display, raise the long-edge cap for a native-size image:

```sh
OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION=1440 \
  ocu call get_app_state --args '{"app":"ZCode"}' \
  | jq -r '.content[] | select(.mimeType=="image/png") | .data' \
  | base64 -d > /tmp/ocu-state.png
```

## Reuse element indexes in one process

Separate `ocu call` processes do not share `element_index`. Use `--calls` for a
known sequence, or `ocu js` when the next action depends on fresh state:

```sh
ocu call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"click","args":{"app":"TextEdit","element_index":"1"}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"hello"}}
]' --no-screenshot
```

`--calls` stops after the first `isError: true` result and sleeps one second
between successful operations by default. Use `--sleep` to change the delay.
