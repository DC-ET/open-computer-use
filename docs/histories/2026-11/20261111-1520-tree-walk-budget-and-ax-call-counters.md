# 树遍历墙钟预算 + AX 调用计数

## 用户诉求

继续按自己的节奏推进性能优化与迭代。

## 问题与定位

钉钉单次 `snapshot` 约 20 s。上一轮已经确认时间全在 `snapshot.tree_walk`，本轮补齐了调用级证据：

- 一次主树遍历共 9 731 次 AX IPC：批量 5 112、单属性 2 903（其中 `AXValue` 2 901）、
  `AXActionNames` 860、`isSettable` 856，平均约 2.0 ms/次；
- 1 500 个节点的批量耗时分布是长尾：p50 0.18 ms、p90 4.50 ms、p99 8.02 ms、max 23.19 ms；
- 轻量批量（8 属性）只省 21–35%，绝对值太小，不值得引入两级缓存；
- `AXValue` 不能并入批量列表：密码字段禁止读值，批量会绕过 `isSecureTextField` 保护。

结论：这类 provider 的慢是长尾导致的，微优化收益有限，只能给遍历设上限。

## 主要改动

### 1. AX 调用计数（可观测性）

`AXSnapshotReadCache` 增加 `CallCounts`，在 `OPEN_COMPUTER_USE_DEBUG_AX_CALLS=1` 时于每次遍历后
向 stderr 输出：

```text
[open-computer-use] ax-calls batch=5112 single=2903 actions=860 settable=856 total=9731 topSingles=AXValue=2901
```

只写 stderr，不改变工具输出。

### 2. 树遍历墙钟预算

- `AccessibilityTreeLimits` 新增 `maxWalkMilliseconds`，默认 15 000 ms；
  `OPEN_COMPUTER_USE_TREE_WALK_BUDGET_MS` 可覆盖，`0` 表示关闭。
- 扫描阶段最多使用 60% 预算，其余留给渲染；`webAreaRewalkAttempts` 的重走循环共享同一个
  截止时间，预算耗尽后不再重走（否则每次重走都会重置预算，反而更慢）。
- 超时返回已收集的节点，并在树末尾追加
  `[Accessibility tree truncated: tree walk budget 15000 ms reached; some nodes were omitted.]`；
  `replacing(...)` 一并传递新字段。

### 3. 测试

- `testWalkBudgetLimitsAreCarriedThroughReplacing`：`replacing` 保留预算字段，默认值大于 0。
- `testZeroWalkBudgetDisablesTheTimeLimit`：预算为 0 时不产生时间截断说明。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AXSnapshotReadCache.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AXSemanticRenderingTests.swift`
- `docs/references/dingtalk-ax-latency.md`
- `docs/RELIABILITY.md`

## 验证

- `swift test`：496 个用例，8 个实机用例按门控跳过，0 失败。
- 钉钉实测：19.99 s / 1 724 行 → 15.37 s / 958 行 + 截断说明；
  `tree_walk` 15 075.7 ms，AX 调用从 9 731 降到 5 615。
- 常规 app 未受影响（单元测试与既有 fixture 全部通过）。

## 已知限制

- 15 s 是折中值：钉钉的完整树需要约 20 s，预算内会丢掉约 44% 的节点（渲染按文档顺序截断）。
  需要完整树时用 `OPEN_COMPUTER_USE_TREE_WALK_BUDGET_MS` 调高。
- 扫描占 60% 预算是一个启发式，未针对不同 provider 做自适应。
- 后续如果要进一步提速，方向应是减少扫描节点数（评估 `scanLimit` 的 4× 倍数）或按角色门控
  `isSettable`，两者都需要真实大列表回归后再动。
