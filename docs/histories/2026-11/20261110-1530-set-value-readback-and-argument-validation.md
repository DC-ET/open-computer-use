# Set-value read-back states and argument validation

## 用户诉求

连续做了一轮真实 GUI 演示后，工具在 Electron 应用上暴露了两类会误导 Agent 的
行为，要求继续修：

- `set_value` 明明写成功，却返回 `isError: true`；
- `press_key` 收到不认识的 `modifiers` 参数时不报错，静默当成按单键 `v`。

同一次会话里还撞上了 `element_index` 在两次动作之间改变含义的问题。

## 主要改动

### 1. `set_value` 三态读回

`verifySetValueReadBack` 原先只有"匹配"和"抛错"两种出口，把"控件根本不暴露
可读值"也当成失败。Agent 看到失败会重试，而重试会让写入落两次。

- 新增 `SetValueReadBack`：`value` / `temporarilyUnavailable` / `unsupported`。
- 新增 `SetValueVerification`：`verified` / `mismatched(actual:)` / `unreadable`。
- `AXUIElementCopyAttributeValue` 返回 `attributeUnsupported` 或 `noValue` 时
  立即判定 `unreadable`，不再空转到 0.6 秒截止时间；其他读失败继续轮询。
- `mismatched` 仍然抛错，但错误文案带上控件实际报告的值（`describeSetValue`
  截断到 80 字符），便于区分"被 normalize"和"完全没写进去"。
- `unreadable` 返回成功，并在结果文本最前面加一行说明：写入已提交、
  值无法验证、重试可能写两次。
- 新增 `ToolCallResult.prependingText`，让这条说明排在快照树之前。

### 2. 清空 Electron 编辑框

真机发现：Chromium contenteditable 在空状态下把 `AXValue` 报成 `"\n"`，
写 `""` 后严格比较必然不相等。新增 `setValueDescribesEmptyText`：请求为空白、
且控件报告的文本 trim 后也为空白时，视为已验证。非空值仍然严格比较。

### 3. 未知参数校验

- `ToolDefinitions.declaredArgumentNames` 从完整 schema 生成每个工具的参数名
  集合；用完整 schema 而不是运行时刻裁剪过的，避免虚拟显示关闭时
  `window_placement` 被误判为未知参数。
- `dispatchTool` 在进入 switch 前拒绝未声明的参数；以 `_` 开头的宿主元数据
  放行。
- 错误信息列出全部可接受参数；`press_key` 收到 `modifiers` 时额外提示
  `{"key": "cmd+v"}` 的写法。
- 未知工具名仍交给 switch 处理，保持原有 `unsupportedTool` 行为。

### 4. 索引失效提示

- `unknown element_index` 增加说明：索引按快照编号，需重新 `get_app_state`
  或改用 `text/role`。
- `set_value` 命中不可设置元素时追加 `staleElementIndexHint`：该索引可能来自
  更早的状态、现在指向别的控件。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SetValueReadBack.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolResult.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/SetValueReadBackTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/UnknownArgumentTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/ElementIndexHintTests.swift`
- `skills/open-computer-use/references/input-troubleshooting.md`
- `skills/open-computer-use/references/output-recipes.md`

## 验证

- `swift test`：489 tests，13 skipped，0 failures。
- Node 测试：61 tests，0 failures。
- `make check-repo` 通过。
- Grok Bot 0.79.3（Electron 42）实测：
  - `set_value(null)` 清空输入框：`isError: false`，输入框回到 Placeholder。
  - `set_value("probe")`：`isError: false`，读回一致。
  - `press_key` 带 `modifiers`：返回
    `press_key: unknown argument modifiers. Accepted: app, key, key_method. Press combinations go in key, for example {"key": "cmd+v"}.`
  - 用不存在的索引：错误含“索引按快照编号”的提示。
  - 对标题元素调用 `set_value`：错误含“该索引可能指向别的控件”的提示。

## 已知限制

- `unreadable` 是成功返回，无法区分“写了但没生效”。这是有意的取舍：
  报失败会让 Agent 重试并造成重复写入。
- 空值等价只在文本类型上生效，数字/布尔仍走严格比较。
- 索引漂移本身没有从根上消除，本批只让失败信息可解释；跨步骤仍需重读状态
  或改用 selector。
- 未知参数校验只覆盖 dispatcher 收到的 JSON；CLI 层的 `--args` 解析不在范围内。
