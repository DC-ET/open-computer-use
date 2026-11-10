import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { PassThrough } from "node:stream";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  inspectCapabilities,
  launcherHelp,
  main,
  parseAppArgs,
  parseJavaScriptArgs,
  parseLSAppInfoPID,
  renderCapabilityReport,
} from "./open-computer-use-cli.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));

function captureStream() {
  const stream = new PassThrough();
  let value = "";
  stream.setEncoding("utf8");
  stream.on("data", chunk => { value += chunk; });
  return { stream, value: () => value };
}

function fakeSpawn(handler) {
  return (command, args) => {
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    const response = handler(command, args) ?? {};
    queueMicrotask(() => {
      if (response.stdout) child.stdout.write(response.stdout);
      if (response.stderr) child.stderr.write(response.stderr);
      child.stdout.end();
      child.stderr.end();
      child.emit("close", response.code ?? 0);
    });
    return child;
  };
}

function makePackage() {
  const packageRoot = mkdtempSync(path.join(os.tmpdir(), "ocu-cli-test-"));
  const scripts = path.join(packageRoot, "scripts", "node-repl");
  const nativePath = path.join(packageRoot, "dist", "fake-native");
  mkdirSync(scripts, { recursive: true });
  mkdirSync(path.dirname(nativePath), { recursive: true });
  for (const name of ["open-computer-use-repl.mjs", "open-computer-use-kernel.mjs", "ocu-config.mjs"]) {
    cpSync(path.join(HERE, name), path.join(scripts, name));
  }
  writeFileSync(nativePath, `#!${process.execPath}
let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => {
  buffer += chunk;
  for (;;) {
    const newline = buffer.indexOf("\\n");
    if (newline < 0) break;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    const request = JSON.parse(line);
    if (request.id === undefined) continue;
    let result = {};
    if (request.method === "initialize") result = { protocolVersion: "2025-06-18", capabilities: { tools: {} } };
    else if (request.method === "tools/call") result = { content: [{ type: "text", text: request.params.name }], isError: false };
    process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: request.id, result }) + "\\n");
  }
});
`, "utf8");
  chmodSync(nativePath, 0o755);
  const platformPackages = {
    [`${process.platform}-${process.arch}`]: { executablePath: ["dist", "fake-native"] },
  };
  return { packageRoot, platformPackages, nativePath, cleanup: () => rmSync(packageRoot, { recursive: true, force: true }) };
}

test("capability report keeps js and repl discoverable when components are missing", () => {
  const packageRoot = mkdtempSync(path.join(os.tmpdir(), "ocu-capability-test-"));
  try {
    const report = inspectCapabilities({
      packageRoot,
      platformPackages: { [`${process.platform}-${process.arch}`]: { executablePath: ["missing-native"] } },
    });
    assert.equal(report.runtime.node.available, true);
    assert.equal(report.capabilities.js.available, false);
    assert.equal(report.capabilities.repl.available, false);
    assert.match(report.capabilities.js.unavailableReasons.join("\n"), /adapter is missing/);
    assert.match(launcherHelp(report), /js <code>/);
    assert.match(launcherHelp(report), /repl/);
    assert.match(launcherHelp(report), /unavailable:/);
    assert.match(renderCapabilityReport(report), /ocu js:\s+unavailable/);
  } finally {
    rmSync(packageRoot, { recursive: true, force: true });
  }
});

test("parses positional, stdin, file, timeout, and JSON options", () => {
  assert.deepEqual(parseJavaScriptArgs(["--timeout", "60000", "--json", "nodeRepl.write(42)"]), {
    timeoutMs: 60_000,
    json: true,
    quiet: false,
    filePath: undefined,
    sourceParts: ["nodeRepl.write(42)"],
  });
  assert.equal(parseJavaScriptArgs(["--timeout", "900000", "-"]).timeoutMs, 300_000);
  assert.equal(parseJavaScriptArgs(["--file", "script.mjs"]).filePath, "script.mjs");
  assert.deepEqual(parseJavaScriptArgs(["--", "-1", "+", "2"]).sourceParts, ["-1", "+", "2"]);
  assert.throws(() => parseJavaScriptArgs(["--file", "script.mjs", "source"]), /exactly one/);
  assert.throws(() => parseJavaScriptArgs(["source"], { replMode: true }), /does not accept positional/);
});

test("main reports structured capabilities without starting native MCP", async () => {
  const fixture = makePackage();
  const output = captureStream();
  const errorOutput = captureStream();
  try {
    const code = await main({
      packageRoot: fixture.packageRoot,
      platformPackages: fixture.platformPackages,
      argv: ["capabilities", "--json"],
      output: output.stream,
      errorOutput: errorOutput.stream,
    });
    assert.equal(code, 0);
    assert.equal(errorOutput.value(), "");
    const report = JSON.parse(output.value());
    assert.equal(report.capabilities.js.available, true);
    assert.equal(report.capabilities.repl.available, true);
    assert.equal(report.runtime.native.path, fixture.nativePath);
  } finally {
    fixture.cleanup();
  }
});

test("ocu js executes positional, stdin, and file source", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const cases = [
    { argv: ["js", "nodeRepl.write(6 * 7)"], input: "", expected: "42\n" },
    { argv: ["js", "-"], input: "nodeRepl.write(await Promise.resolve('stdin'))", expected: "stdin\n" },
  ];
  const sourcePath = path.join(fixture.packageRoot, "source.mjs");
  writeFileSync(sourcePath, "nodeRepl.write('file')", "utf8");
  cases.push({ argv: ["js", "--file", sourcePath], input: "", expected: "file\n" });

  for (const entry of cases) {
    const input = new PassThrough();
    input.end(entry.input);
    const output = captureStream();
    const errorOutput = captureStream();
    const code = await main({
      packageRoot: fixture.packageRoot,
      platformPackages: fixture.platformPackages,
      argv: entry.argv,
      input,
      output: output.stream,
      errorOutput: errorOutput.stream,
    });
    assert.equal(code, 0, errorOutput.value());
    assert.equal(output.value(), entry.expected);
  }
});

test("ocu js returns a non-zero exit when evaluation times out", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const output = captureStream();
  const errorOutput = captureStream();
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["js", "--timeout", "100", "while (true) {}"],
    output: output.stream,
    errorOutput: errorOutput.stream,
  });
  assert.equal(code, 1);
  assert.match(output.value(), /timed out after 100 ms/);
});

test("parseJavaScriptArgs accepts --quiet without changing other options", () => {
  const options = parseJavaScriptArgs(["--quiet", "--timeout", "1234", "code"]);
  assert.equal(options.quiet, true);
  assert.equal(options.timeoutMs, 1234);
  assert.deepEqual(options.sourceParts, ["code"]);
});

test("ocu js --quiet omits the JavaScript API guidance", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const output = captureStream();
  const errorOutput = captureStream();
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["js", "--quiet", "var app = await cua.getApp('TextEdit', { initialState:false }); nodeRepl.write('ok')"],
    output: output.stream,
    errorOutput: errorOutput.stream,
  });
  assert.equal(code, 0, errorOutput.value());
  assert.equal(output.value().trim(), "ok");
});

test("parseAppArgs validates actions, bundle ids and timeouts", () => {
  assert.deepEqual(parseAppArgs(["status", "dev.zcode.app", "--json"]), {
    action: "status",
    bundleId: "dev.zcode.app",
    timeoutMs: 10_000,
    json: true,
    help: false,
  });
  assert.equal(parseAppArgs(["quit", "dev.zcode.app", "--timeout", "2.5"]).timeoutMs, 2_500);
  assert.equal(parseAppArgs(["activate", "dev.zcode.app"]).action, "activate");
  assert.throws(() => parseAppArgs(["open", "dev.zcode.app"]), /app expects one of/);
  assert.throws(() => parseAppArgs(["status"]), /requires a bundle identifier/);
  assert.throws(() => parseAppArgs(["status", "bad id"]), /Invalid bundle identifier/);
  assert.throws(() => parseAppArgs(["status", "dev.zcode.app", "--timeout", "0"]), /positive number/);
});

test("parseLSAppInfoPID reads the pid line and ignores an empty result", () => {
  assert.equal(parseLSAppInfoPID('"pid"=4321\n'), 4321);
  assert.equal(parseLSAppInfoPID(""), undefined);
  assert.equal(parseLSAppInfoPID("no pid here"), undefined);
});

test("app status reports running state as JSON", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const output = captureStream();
  const errorOutput = captureStream();
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["app", "status", "dev.zcode.app", "--json"],
    output: output.stream,
    errorOutput: errorOutput.stream,
    platform: "darwin",
    spawnFn: fakeSpawn(command => command === "lsappinfo" ? { stdout: '"pid"=321\n' } : {}),
  });
  assert.equal(code, 0, errorOutput.value());
  assert.deepEqual(JSON.parse(output.value()), {
    bundleId: "dev.zcode.app",
    action: "status",
    running: true,
    pid: 321,
  });
});

test("app quit waits for the process to disappear", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const output = captureStream();
  const errorOutput = captureStream();
  let statusCalls = 0;
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["app", "quit", "dev.zcode.app", "--timeout", "1"],
    output: output.stream,
    errorOutput: errorOutput.stream,
    platform: "darwin",
    spawnFn: fakeSpawn(command => {
      if (command === "lsappinfo") {
        statusCalls += 1;
        return statusCalls === 1 ? { stdout: '"pid"=321\n' } : {};
      }
      if (command === "osascript") return {};
      throw new Error(`unexpected command: ${command}`);
    }),
  });
  assert.equal(code, 0, errorOutput.value());
  assert.equal(output.value().trim(), "quit dev.zcode.app");
});

test("app quit reports a remaining process as a non-zero result", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const output = captureStream();
  const errorOutput = captureStream();
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["app", "quit", "dev.zcode.app", "--timeout", "1"],
    output: output.stream,
    errorOutput: errorOutput.stream,
    platform: "darwin",
    spawnFn: fakeSpawn(command => command === "lsappinfo" ? { stdout: '"pid"=321\n' } : {}),
  });
  assert.equal(code, 1);
  assert.match(output.value(), /still running \(pid 321\)/);
});

test("ocu repl preserves bindings and reset discards them", async t => {
  const fixture = makePackage();
  t.after(fixture.cleanup);
  const input = new PassThrough();
  input.end([
    "var answer = 40; nodeRepl.write(answer)",
    "answer += 2; nodeRepl.write(answer)",
    ".editor",
    "var object = {",
    "  value: answer,",
    "};",
    "nodeRepl.write(object.value)",
    ".end",
    ".reset",
    "nodeRepl.write(typeof answer)",
    ".exit",
  ].join("\n"));
  const output = captureStream();
  const errorOutput = captureStream();
  const code = await main({
    packageRoot: fixture.packageRoot,
    platformPackages: fixture.platformPackages,
    argv: ["repl"],
    input,
    output: output.stream,
    errorOutput: errorOutput.stream,
  });
  assert.equal(code, 0, errorOutput.value());
  assert.equal(output.value(), "40\n42\n42\nOpen Computer Use JavaScript session reset\nundefined\n");
});
