# Selector-based element actions

## 用户诉求

继续下一批优化。优先解决跨进程 `element_index` 失效的问题：让
`click` / `set_value` / `scroll` / `perform_secondary_action` 可以直接用
`text` + `role` 定位控件，而不必先拿索引再在另一个进程里使用。

## 主要改动

### 1. Dispatcher 选择器解析

- 新增 `SelectorArguments`，从工具参数读取 `text` / `role` / `exact` /
  `max_nodes`。
- 新增 `resolveElementIndex(app:arguments:required:)`：
  - 有 `element_index` 时直接使用；
  - 没有索引但有 `text`/`role` 时，调用同一个 `query` 实现解析；
  - 要求恰好一个匹配；0 个或多个都返回明确错误，不执行动作；
  - `element_index` 与 `text`/`role` 同时出现时报冲突。
- `click` 额外检查 `x/y` 与 selector 不能同时出现。
- `set_value` / `scroll` / `perform_secondary_action` 的 `element_index` 改为
  可选；缺少索引和 selector 时返回
  `Missing required argument: element_index or text/role`。
- `select_text` 未纳入本批，因为它的 `text` 参数表示“要选中的文本”，与
  selector 的 `text` 语义冲突；仍使用 `element_index`。

### 2. 选择器与 query 祖先提升的配合

- `ElementRecord` 新增 `targetedMatchCriteria`，记录实际匹配该记录的条件。
- `targetedSearchDirect` 保存原始 criteria。
- `targetedSearchPromotingAncestorRole` 对被提升的祖先保存 role-only
  criteria。
- `registerTargetedElement` 使用记录自身的 criteria 注册目标。
- 这样 `query` 返回的 AXRow（文本在子节点）在被 `click` 重新校验几何时，
  不会因为“行本身没有文本”而误报 `Query target changed`。

### 3. Tool schema

- `click` / `set_value` / `scroll` / `perform_secondary_action` 增加可选
  `text`、`role`、`exact`、`max_nodes` 字段。
- 对应 `required` 数组移除 `element_index`，保留其他必填参数。
- 更新工具描述和 CLI/SKILL 示例。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/output-recipes.md`

## 验证

- `swift test`：475 tests，13 skipped，0 failures。
- Node 测试：61 tests，0 failures。
- `make check-repo` 通过。
- Finder 实测：
  - `click({"app":"Finder","text":"桌面","role":"AXRow","exact":true})`
    返回 `isError: false`，并返回 Finder 状态。
  - 同时传 `element_index` 和 `text/role` 返回
    `Use either element_index or text/role, not both`。
  - 单独 `query` 仍返回 `AXRow`，索引可继续用于同一进程内的动作。

## 已知限制

- Selector 解析复用 `query`，因此只在 macOS runtime 可用；不支持 fixture
  app 的 targeted lookup。
- 一个 selector 必须恰好匹配一个控件；当前不做“选择第一个”的隐式行为。
- `select_text` 仍需要 `element_index`。
- JS API 暂未增加 selector 参数；`ocu js` 中可先 `app.query(...)` 再
  `app.click(index)`。
