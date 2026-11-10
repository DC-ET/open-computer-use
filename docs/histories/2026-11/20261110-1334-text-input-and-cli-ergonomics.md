# Text input fallback and CLI ergonomics

## 用户诉求

在一个 Electron 应用的真实任务中，`type_text` 多次返回成功但输入框没有变化；
`set_value` 无法验证；中文只能通过剪贴板粘贴，且覆盖了用户原有剪贴板。
同时，`ocu call get_app_state` 默认输出 base64 截图，`ocu js` 每次都打印完整
JavaScript API 指引，不适合 Agent 消费。要求逐项优化、本地验证后提交。

## 主要改动

### 1. `type_text` 写入验证与键盘回退

- `typeTextUsingAccessibility` 在 web/Electron 控件上写入 `AXSelectedText`
  后，读取 `AXValue` 并等待最多 250 ms。如果值没有变化，返回 `false`，
  让调用方进入已有的 Unicode 键盘事件回退。
- 键盘回退后，对空的 web 文本控件再次验证 `AXValue`；如果仍未变化，
  返回明确错误，避免 `isError: false` 的静默成功。
- `hasAncestorRole` 增加可选 `maxDepth`。文本输入检测使用 64 层，
  因为真实 Electron 输入框在 AX 树中的深度超过原来的 12 层，
  否则无法识别 `AXWebArea`。
- 新增纯函数 `shouldFallbackAfterAXSelectedTextWrite` 和
  `shouldVerifyKeyboardTextWrite`，并补充单元测试。

### 2. CLI 输出与参数

- `open-computer-use call` 新增 `--no-screenshot`。它只对
  `get_app_state` 注入 `include_screenshot: false`；调用方显式传入的
  `include_screenshot` 优先。
- `open-computer-use snapshot` 新增 `--no-screenshot`，等价于
  `--include-screenshot false`。
- `ocu js` / `ocu repl` 新增 `--quiet`，过滤一次性的
  “Open Computer Use JavaScript API” 指引；`--json` 仍输出单个 JSON 结果。
- 补充 CLI help 文本与 Node CLI 测试。

### 3. SKILL 文档

新增四份 reference：

- `references/input-troubleshooting.md`：焦点检查、输入回退阶梯、
  Electron/Web 控件、剪贴板编码与恢复、写入后验证。
- `references/output-recipes.md`：`--no-screenshot`、`--quiet`、截图落盘、
  同一进程复用 `element_index`。
- `references/app-recipes.md`：ZCode/Electron、Finder、TextEdit、Chrome 的
  起始命令与已知坑。
- `references/app-lifecycle.md`：优雅退出、重新启动、激活、未保存弹窗处理。

`SKILL.md` 增加 CLI-first workflow、输入与验证规则，并更新 references 索引。

## 设计动机

- 对 web/Electron 文本控件，AX 写入可能“成功但无效果”。只报告成功会让
  Agent 误判任务完成，因此必须验证可观察结果，再决定是否回退。
- 回退阶梯保留原生 AppKit 的 AX 优先路径，只在可观察值未变化时使用键盘，
  避免在原生控件上重复输入。
- CLI 默认输出应适合 Agent：状态默认不带截图，脚本输出默认不带指引；
  需要像素时再显式请求。
- 把 ZCode 的实测坑写进 SKILL，避免同类问题依赖聊天上下文。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/node-repl/open-computer-use-cli.mjs`
- `scripts/node-repl/open-computer-use-cli.test.mjs`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/input-troubleshooting.md`
- `skills/open-computer-use/references/output-recipes.md`
- `skills/open-computer-use/references/app-recipes.md`
- `skills/open-computer-use/references/app-lifecycle.md`

## 验证

- `swift test`：467 tests，13 skipped，0 failures。
- `node --test scripts/node-repl/*.test.mjs scripts/tests/*.test.mjs`：56 tests，
  0 failures。
- `make check-docs` 通过，`npm run package:skill` 成功。
- 在 ZCode（Electron）中，用独立 Dev app 运行新构建：
  `type_text` 成功写入中文“测试”，AX 状态显示 `Value: 测试`；
  清空后输入框恢复 placeholder。
- 对 Finder 执行 `type_text` 返回明确错误
  `type_text requires a focused editable text element...`，不再静默成功。

## 已知限制

- `type_text` 的键盘回退仍要求目标窗口能接收进程定向键盘事件；如果应用完全
  忽略这类事件，会返回明确错误而不是继续伪装成功。
- 直接运行裸 CLI（关闭 app-agent proxy）在真实桌面 app 上仍可能返回
  `cgWindowNotFound`；真实 GUI 操作继续走 app-agent / app bundle 路径。
- 本次没有新增剪贴板 paste 工具。需要剪贴板时，调用方必须先保存并恢复所有
  pasteboard 类型；SKILL 已记录该约束。
