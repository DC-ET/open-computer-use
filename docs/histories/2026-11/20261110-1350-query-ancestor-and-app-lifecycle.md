# Query ancestor promotion and app lifecycle commands

## 用户诉求

上一批已完成并合并到 `main`。继续下一批：优化 `query` 对子节点文本的匹配，
让 `query({role:"AXRow", text:"桌面"})` 能返回行本身；同时增加 macOS 的
`ocu app status|activate|launch|quit` 生命周期命令。

## 主要改动

### 1. `query` 后代文本提升

- `TargetedAX.targetedSearch` 先做原有 direct search。
- 当 `role` 和 `text` 都存在、且 direct search 没有结果时，改用 text-only
  搜索，然后从每个文本匹配节点向上最多 64 层查找最近的、role 匹配的祖先。
- 用 `AXSearchNode` 去重；保留 `stop_reason` / `visited_nodes` 元数据。
- 不在 direct search 有结果时改变行为，因此普通文本查询和已命中的
  role+text 查询保持原语义。
- 新增 `targetedRecordMatches` 的 role-only 单测，覆盖 `AXRow` / `row` 前缀。

### 2. `ocu app` 生命周期命令

新增 macOS-only 的 launcher 命令：

```text
ocu app status <bundle-id> [--json]
ocu app activate <bundle-id> [--json]
ocu app launch <bundle-id> [--timeout <seconds>] [--json]
ocu app quit <bundle-id> [--timeout <seconds>] [--json]
```

- 使用 `lsappinfo info -only pid -app <bundle-id>` 检查运行状态，不依赖
  本地化 app 名称，也不需要额外 TCC 权限。
- `activate` / `quit` 使用 `osascript` 的 `on run argv`，bundle id 作为参数
  传入，避免 AppleScript 字符串拼接。
- `launch` 使用 `open -b`，轮询等待进程出现。
- `quit` 轮询等待进程退出；超时仍运行时返回非零，并提示检查未保存弹窗。
- 支持 `--json` 输出，便于脚本和 Agent 消费。
- Windows / Linux 明确返回“currently require macOS”。

### 3. 文档

- `SKILL.md` 增加 `query` 祖先提升说明和 `ocu app` 示例。
- `references/app-lifecycle.md` 改为以 `ocu app` 为主，AppleScript /
  `lsappinfo` 作为手动 fallback。
- `references/app-recipes.md` 更新 Finder 的 `AXRow` 查询示例。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/TargetedQuerySafetyTests.swift`
- `scripts/node-repl/open-computer-use-cli.mjs`
- `scripts/node-repl/open-computer-use-cli.test.mjs`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/app-lifecycle.md`
- `skills/open-computer-use/references/app-recipes.md`

## 验证

- `swift test`：472 tests，13 skipped，0 failures。
- Node 测试：61 tests，0 failures。
- `make check-docs` 通过。
- Finder 实测：
  - `query({"app":"Finder","text":"桌面","role":"AXRow","exact":true})`
    返回 1 条 `AXRow`（bounds `8,135,167,32`）。
  - 同样参数的 text-only 查询仍返回 `AXStaticText`。
- 计算器实测（`com.apple.calculator`）：
  - `app status` → not running
  - `app launch` → launched pid 70710
  - `app status --json` → `{running:true,pid:70710}`
  - `app activate` → activated
  - `app quit --timeout 5` → quit
  - `app status` → not running

## 已知限制

- `query` 的祖先提升只在 direct search 为空时触发；如果同时存在多个角色，
  仍按单角色查询。64 层是当前上限。
- `ocu app` 当前仅支持 macOS；`quit` 不会自动处理未保存弹窗。
- `ocu app` 没有实现 `list`，运行中的应用列表继续使用
  `ocu call list_apps`。
