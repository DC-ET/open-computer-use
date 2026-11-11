# 跨 Space 门控定性 + 钉钉 snapshot 延迟定位

## 用户诉求

基线报告里还留着三项待处理：跨 Space 实机门控确定性失败、钉钉 23 s snapshot、
Chromium 系 app 输入未回读。要求继续推进这一批任务。

## 结论

### 1. 跨 Space 失败不是产品回归，是环境限制

用两个独立探针验证：

- 探针 v1：切到另一个 Space 后，`SLSGetActiveSpace` 返回目标 space（320），
  但用作参照的真实窗口始终 `onscreen = true`；
- 探针 v2：切换前后在屏窗口集合完全一致（64 个窗口，`disappeared = 0`，`appeared = 0`），
  恢复到原 space 后集合也相同。

即 `SLSManagedDisplaySetCurrentSpace` 在 macOS 26.6.2 上只更新内部 active space 值，
桌面没有真正切换。测试随后启动的 Chrome 只能落在用户当前 Desktop 上，后续断言因此失败。

处理：`CrossSpaceLiveTests` 在切换后比较在屏窗口集合，识别出 no-op 就 `XCTSkip` 并给出原因，
不再把环境限制误报成产品失败。

### 2. 钉钉 23 s 的瓶颈是 AX provider 单次调用慢

- 分阶段计时：`snapshot.capture_hw` 31.9 ms、`snapshot.window_capture` 62.5 ms、
  **`snapshot.tree_walk` 19 642.9 ms**；
- `sample` 采样：调用栈全部阻塞在 `AXUIElementCopyAttributeValue` /
  `AXUIElementCopyMultipleAttributeValues` 的 `mach_msg` 上，等钉钉 provider 返回；
- 独立探针复刻批量读取：900 节点、约 4 000 次调用、墙钟 11.9 s，平均每次约 3 ms；
  会话列表在深度 4 展开成 577 个节点，`AXTable` 有 563 个子节点。

结论：provider 单次调用慢 × 每元素多次 IPC（批量 + 批量外单读 + actionNames + isSettable）。
优化方向（减少每元素调用、给 tree walk 设墙钟预算、大表分段）记录在
`docs/references/dingtalk-ax-latency.md`，本轮未实施。

### 3. `typed=false` 不是 PARK 副作用

非 PARK 模式对照：语雀、钉钉仍然 `typed=false`（`cleared=true` 在从未输入成功时天然成立），
同轮 Mao 为 `typed=true`。说明这是这两个 app 的后台输入边界，需要单独定位；
该轮 Chrome 因为没有空白输入框没有进入输入测试。

### 4. 指针位移是交互噪声

非 PARK 对照轮位移 165 pt / 323 pt，远超程序性抖动；click 默认不允许 global 指针回退
（需要显式设置 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`），因此判定为用户在
测试期间移动了鼠标。指针断言只在无人值守时才有判定意义。

## 主要改动

- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/CrossSpaceLiveTests.swift`：
  新增 `onScreenWindowIDs()`，切换 Space 后先判断是否真的换了桌面，no-op 时 `XCTSkip`。
- `docs/references/dingtalk-ax-latency.md`：新增延迟剖析记录。
- `docs/references/baseline-2026-11-11.md`：追加本轮诊断结论。
- `docs/references/README.md`：登记新文档。

## 受影响文件

- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/CrossSpaceLiveTests.swift`
- `docs/references/dingtalk-ax-latency.md`
- `docs/references/baseline-2026-11-11.md`
- `docs/references/README.md`

## 验证

- `OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests`：
  1 test skipped（`SLSManagedDisplaySetCurrentSpace reported success but the desktop did not switch`），
  0 failures，1.55 s。
- `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 OPEN_COMPUTER_USE_DEBUG_TIMING=1 ... snapshot "钉钉"`：
  `tree_walk 19 642.9 ms`，总 19.86 s。
- 非 PARK AppMatrix（语雀 / 钉钉 / Chrome）：语雀、钉钉 `typed=false`，Mao `typed=true`。
- `swift test`：496 个用例，8 个实机用例按门控跳过，0 失败；`check-docs` / `check-repo-hygiene` 通过。

## 已知限制

- 跨 Space 能力本身仍未实测（需要手工 Mission Control 切换或可切换的 macOS），
  自动门控只保证在有真实切换的机器上才会执行。
- 钉钉的优化尚未实施；若要实施，需要先在真实大列表上验证 tree walk 预算不会漏掉可操作元素。
- 语雀 / 钉钉的 `typed=false` 需要继续定位（点击是否真的聚焦到页面输入框、是否走了 AX 输入路径）。
