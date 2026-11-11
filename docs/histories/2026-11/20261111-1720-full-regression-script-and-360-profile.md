# 全量回归脚本 + 360 浏览器 AX 剖析

## 用户诉求

继续：给慢 provider 补第二个样本，并把「全量回归」固化成一条命令。

## 360 极速浏览器 Pro 剖析

同一台机器实测：`tree_walk` 10 958.2 ms、总 11.91 s、**23 172 次 AX IPC**
（批量 14 642、单属性 6 205 全部是 `AXValue`、actions 1 170、settable 1 155），输出 4 505 行，
未触发 15 s 预算。

与钉钉同族但形态不同：单次调用更快（约 0.47 ms），树更大。关键发现是**批量数远超扫描上限**
（14 642 > `scanLimit` 4 800），说明渲染阶段对子孙元素的摘要遍历（`summarizedGenericText`、
`flattenedRowTexts` 等）是大头，而不只是扫描。

因此两件事被评估后不采纳：`isSettable` 按角色门控（只占 5%，收益可忽略）、扫描倍数 4×→2×
（常规 app 输出完全一致，收益边际）。结论都留档在 `docs/references/dingtalk-ax-latency.md`。

## 新增：`scripts/run-full-regression.sh`

一条命令跑完整回归：

- 默认：构建、`swift test`、node / python / go 测试、仓库检查 + smoke、stress、实机门控
  （sky_click / sky_key / occlusion / cross-space / agent display）、后台输入基准；
- `--skip-gui`：只跑无 GUI 部分；
- `--include-app-matrix`：额外跑真实 app 矩阵（会向运行中的 app 输入标记）；
- `--loops N` / `--bench-cycles N`：调整 stress 与基准规模；
- 每个步骤日志落到临时目录，末尾输出 JSON 汇总（`ok`、每步状态与耗时、失败清单、日志目录）；
- 兼容 macOS 自带 bash 3.2，GUI 步骤会接管窗口与输入，脚本头部与 `--help` 都有提醒。

## 受影响文件

- `scripts/run-full-regression.sh`（新增）
- `docs/RELIABILITY.md`
- `docs/references/dingtalk-ax-latency.md`
- `docs/references/README.md`

## 验证

- `bash -n` 通过；`--skip-gui`：6 步、31 s，全部通过。
- GUI 路径（`--loops 1 --bench-cycles 3`）：14 步、90 s，全部通过；
  cross-space 自动 skip（按设计），app matrix 按预期跳过。
- `check-docs` / `check-repo-hygiene` 通过。

## 已知限制

- GUI 步骤需要已授权辅助功能/屏幕录制的图形会话，不能在无头环境跑。
- stress 与基准的默认轮数偏小（5 / 10），完整压测仍建议显式传更大的 `--loops`。
- app matrix 的 `cleared` 口径在「标记文本已存在于页面其他位置（例如聊天记录）」时会假阴性。
