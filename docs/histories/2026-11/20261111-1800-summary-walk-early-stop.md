# 摘要遍历提前终止：360 浏览器快照提速 32%

## 用户诉求

继续推进性能优化：处理 360 极速浏览器 Pro 这类大树快照的耗时大头。

## 定位

上一轮已经确认 360 的批量调用（14 642）远超扫描上限（4 800），大头在渲染阶段对子孙元素的
摘要遍历。读代码后发现关键约束：`summarizedGenericText` 只有在「≤8 段文本且 ≤220 字符」时才会
合并（`shouldMergeTextOnlySiblings`），也就是说**超过上限的摘要注定被丢弃**。

## 改动

- 新增 `SummaryTextCollector`：保持与 `descendantTextsForSummary` 相同的深度优先顺序，但在
  9 段文本 / 221 字符时停止采集；
- `summarizedGenericText` 改用该采集器；
- 链接摘要（`summaryTextForLink`）仍走原有不限量路径，避免改变链接文本。

行为等价性：提前停止只发生在那两个上限被超过之后，而这两个条件本身就会让
`shouldMergeTextOnlySiblings` 返回 false，所以摘要结果不变。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AXSemanticRenderingTests.swift`
- `docs/references/dingtalk-ax-latency.md`

## 验证

- `swift test`：500 个用例，8 个实机用例跳过，0 失败；
- 360 极速浏览器 Pro：`tree_walk` 10 958 → 7 220 ms，总耗时 11.91 → 8.07 s，
  AX 调用 23 172 → 21 406；
- 背靠背 A/B（同一 app、两个二进制）：Chrome 输出完全一致；访达的 `ZIP` / `ZIP归档` 差异在
  同一二进制重复运行时同样出现，属于 app 自身波动；
- 新增测试：`testGenericGroupWithFewTextsIsSummarized`、
  `testGenericGroupBeyondMergeLimitIsNotSummarized`。

## 已知限制

- 钉钉这类成本集中在扫描与 `AXValue` 单读的 app 不受益（仍由 15 s 遍历预算兜底）。
- 摘要遍历的深度上限（8 层）与既有 `summaryImageDescendants`（4 层）保持不变。
- 链接摘要仍可能遍历较多子孙；如果后续发现链接是热点，再单独收敛。
