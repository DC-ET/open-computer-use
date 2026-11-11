# AppMatrix 字段过滤与指针断言策略

## 用户诉求

继续推进实测与验证的下一批：把 AppMatrix 的假失败压下去，让矩阵结果可信。

## 问题

1. **禁用输入框被当成产品失败**：语雀的候选字段是
   `文本栏 (disabled) Placeholder: 搜索`，矩阵仍尝试点击与输入，结果 `typed=false`，
   看起来像输入功能坏了，实际是字段不可编辑。
2. **指针断言在交互环境下必然误报**：两次实测分别出现 0.24 pt（虚拟屏缩放噪声）、
   23 pt 与 76 pt（用户移动鼠标）的位移；产品默认不允许全局指针回退，click 不会移动指针。
   只要有人在用这台 Mac，精确断言就会把会话变成失败。

## 主要改动

- 候选输入框过滤新增 `isEnabled(element)`（`kAXEnabledAttribute`），PARK 路径与主路径共用；
  跳过禁用字段后，语雀正确输出 `no empty text field -> no input test`。
- 指针检查改为：仅当 `OPEN_COMPUTER_USE_APP_MATRIX_ASSUME_IDLE=1` 时断言漂移 ≤ 1 pt，
  否则超过 1 pt 只打印
  `MATRIX note: pointer moved <n>pt …`。前台 app 不变仍然是硬断言。
- 更新测试文件头部说明，写清新的字段过滤与指针策略。

## 受影响文件

- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AppMatrixLiveTests.swift`
- `docs/references/baseline-2026-11-11.md`（追加诊断细化）
- `docs/references/dingtalk-ax-latency.md`（多 app 快照对照表）

## 验证

- 精简矩阵（仅语雀 + Mao）：0 失败；语雀跳过输入测试，Mao `typedInField=true`，
  指针位移 76 pt 以 note 形式输出。
- `swift test`：498 个用例，8 个实机用例按门控跳过，0 失败。

## 关联发现

钉钉的 `typed=false` 与语雀不同源：它的搜索框是 enabled + settable，手动复现
`click(element_index: 11)` → `type_text("zq7x")`（默认与显式 `sky_key` 两条路径）都返回
`isError=false`，但两次快照都找不到标记、字段值也未变化——属于产品级问题：点击后焦点未
真正落入 Web 输入框，且 `type_text` 缺少回读校验。已记入基线报告的待修项。
