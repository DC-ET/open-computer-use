# 钉钉 AX snapshot 延迟剖析（2026-11-11）

`get_app_state` / `snapshot` 对钉钉单次耗时 15–24 s，而同机其他 app 都在 1 s 上下。
这份文档记录定位过程、证据和可选优化方向，命令都可以重跑。

## 症状

AppMatrix（PARK）一轮里的对照：

| app | 节点数 | snapshot |
| --- | --- | --- |
| 飞书 | 485 | 922 ms |
| Cursor | 588 | 2 931 ms |
| Finder | 161 | 1 431 ms |
| **钉钉** | **707** | **23 729 ms** |

同一轮里钉钉的 park 后 snapshot 22 217 ms，restore 24 707 ms。非 PARK 模式复测：
snapshot 22 164 ms，click+type 47 614 ms。

## 分阶段计时

```bash
OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 OPEN_COMPUTER_USE_DEBUG_TIMING=1 \
  ./.build/debug/OpenComputerUse snapshot "钉钉"
```

| 阶段 | 耗时 |
| --- | --- |
| `snapshot.capture_hw` | 31.9 ms |
| `snapshot.window_capture` | 62.5 ms |
| **`snapshot.tree_walk`** | **19 642.9 ms** |
| 总耗时 | 19.86 s |

截图不是瓶颈，时间全在 AX 树遍历。

> 注意：默认走 app-agent 代理时，`OPEN_COMPUTER_USE_DEBUG_TIMING=1` 不会生效——重活在
> 常驻 agent 进程里，环境变量没有传过去。剖析必须加 `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1`。

## 采样

在 snapshot 运行期间对进程做 `sample`，调用栈几乎全部停在：

```text
AXUIElementCopyAttributeValue       3882 samples
  _AXUIElementCopyAttributeValue
    _AXMIGCopyAttributeValue
      mach_msg  ← 等待目标进程的 AX provider
AXUIElementCopyMultipleAttributeValues  2789 samples（同样阻塞在 mach_msg）
```

即客户端本身没有计算热点，是在等钉钉的 accessibility provider 返回。

## 逐元素复现

用独立探针复刻同样的批量读取（19 个属性一次 `AXUIElementCopyMultipleAttributeValues`），
同时按元素统计：

- 900 个节点、约 4 000 次 AX 调用，墙钟 11.9 s → **平均每次 AX 调用约 3 ms**；
- 最慢的元素是 `AXTable children=563`，单次批量读取 20 ms；大量 `AXImage` 为 11–13 ms；
- 钉钉窗口的会话列表在深度 4 展开成 577 个节点，这是节点数的主要来源。

## 根因

钉钉的 AX provider 单次调用就要约 3 ms，而 `TreeRenderer` 对每个元素不止一次调用：

1. 首次读取时一次批量 19 属性（`AXSnapshotReadCache.readBatch`）；
2. 批量列表之外的属性（如 `AXValue`、`AXSelectedText`）再单独读；
3. `actionNames` 一次；
4. `isSettable` 按属性各一次。

700 多个元素 × 多次 IPC × 3 ms ≈ 20 s。这与 `tech-debt-tracker.md` 里
「大型控件树 provider 耗时」是同一类问题，但这次的具体成因是**单次调用慢**，
不是候选数量多。

## 可选优化方向（未实施）

1. **减少每元素调用次数**：对不可操作元素跳过 `actionNames` / `isSettable`；
   把 `AXValue` 等高频属性并入批量列表，避免单独 IPC。
2. **时间预算**：给 tree walk 设墙钟上限（例如 5 s），超时后返回已收集的部分树并明确标注
   `tree truncated: provider slow`，而不是让整个 `get_app_state` 卡 20 s。
3. **大表分段**：对 500+ 子节点的 `AXTable` / `AXList` 分段读取，先返回可操作候选。
4. **复用**：同一 session 内重复 snapshot 时复用未变化的子树（需要失效判定，风险较高）。

方向 1 和 2 收益/风险比最好；方向 3 需要真实大列表回归；方向 4 需要先解决失效语义。

## 已评估未采纳：扫描倍数 4× → 2×

`AccessibilitySnapshot` 的 `scanLimit = max(64, min(limit, 2500) * 4)` 是 #145 为「大列表挤掉后面的
嵌套按钮」引入的。实验把倍数降到 2× 后横比（同一台机器、同一轮）：

| app | 4× | 2× |
| --- | --- | --- |
| 访达 | 361 行 | 361 行 |
| Cursor | 591 行 | 591 行 |
| Google Chrome | 654 行 | 654 行 |
| 钉钉 | 1 255 行 / 11 按钮 / 2 文本栏 | 1 266 行 / 11 按钮 / 2 文本栏 |

常规 app 输出完全一致；钉钉的控件数量一致，行数差异在噪声范围；13 个渲染语义测试全部通过。
结论：收益边际，而 4× 服务于真实修复场景，维持原值不动。

## 复现命令

```bash
# 分阶段计时
OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 OPEN_COMPUTER_USE_DEBUG_TIMING=1 \
  ./.build/debug/OpenComputerUse snapshot "钉钉"

# 采样（另开一个 shell，等 snapshot 起来后执行）
sample $(pgrep -f "OpenComputerUse snapshot 钉钉" | head -1) 18 -file /tmp/dingtalk-sample.txt
```

## 调用计数（第二轮）

给 `AXSnapshotReadCache` 加了 `OPEN_COMPUTER_USE_DEBUG_AX_CALLS=1` 的计数输出后，一次 19.97 s 的
主树遍历是：

| 调用类型 | 次数 |
| --- | --- |
| 批量（19 属性） | 5 112 |
| 单属性 | 2 903（其中 `AXValue` = 2 901） |
| `AXActionNames` | 860 |
| `AXUIElementIsAttributeSettable` | 856 |
| 合计 | 9 731 |

约 2.0 ms/次。`AXValue` 不能并入批量列表：密码字段明确禁止读取其值，批量读取会绕过
`isSecureTextField` 的保护。

全树 1 500 个节点的批量耗时分布：p50 = 0.18 ms、p90 = 4.50 ms、p99 = 8.02 ms、max = 23.19 ms。
慢的是长尾（`AXTable` 23 ms、`AXCell`/`AXStaticText` 8–10 ms），不是平均成本。

轻量批量实验（扫描只需要 8 个属性）：浅层元素 0.17 ms vs 0.22 ms（省 21%），大表行 0.08 ms vs
0.13 ms（省 35%）。省下的绝对值太小，不值得引入两级批量缓存。

## 已实施：树遍历墙钟预算

结论是这类 provider 只能靠限时兜底，不能靠微优化：

- `AccessibilityTreeLimits.maxWalkMilliseconds` 默认 15 000 ms，`OPEN_COMPUTER_USE_TREE_WALK_BUDGET_MS`
  可覆盖；`0` 表示关闭预算。
- 扫描最多用 60% 预算，剩下留给渲染；`webAreaRewalkAttempts` 的重走循环共享同一个截止时间，
  预算耗尽后不再重走。
- 超出预算时返回已收集的节点，并在树末尾追加
  `[Accessibility tree truncated: tree walk budget 15000 ms reached; some nodes were omitted.]`。

实测钉钉：19.99 s / 1 724 行 → **15.37 s / 958 行 + 截断说明**。常规 app 不受影响（496 个单元
测试全部通过）。如果调用方需要完整树，可以显式调高该预算。

改动落地后的多 app 快照对照（同一台机器、同一轮）：

| app | 耗时 | 行数 | 是否截断 |
| --- | --- | --- | --- |
| Google Chrome | 0.57 s | 292 | 否 |
| 飞书 | 0.66 s | 482 | 否 |
| Cursor | 0.67 s | 591 | 否 |
| 访达 | 1.56 s | 357 | 否 |
| 钉钉 | 15.27 s | 1 194 | 是 |
