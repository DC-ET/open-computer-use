# 文本输入可靠性：点击聚焦与 sky_key 回读

## 用户诉求

继续按节奏推进：先给 `type_text` 补回读校验，再处理后端点击的焦点语义。

## 问题

1. **后台点击不转移 app 内焦点**：点击钉钉搜索框后读取 `AXFocusedUIElement`，焦点仍是消息
   输入框；随后 `type_text` 把标记写进了消息框（实测读到 `zq7xzq7x`）。「点击搜索框 → 输入」
   的自然用法会静默输错位置。
2. **`type_text` 的 `sky_key` 路径没有回读校验**：按键投递失败时也返回干净的快照结果，
   调用方无法察觉。

## 主要改动

### 1. click 后对文本控件尽力聚焦

`focusTextEntryIfPossible(_:)`：当被点击元素是 `AXTextField` / `AXTextArea` / `AXComboBox` /
`AXSearchField` 且 `AXFocused` 可写时，显式设置焦点（best effort，忽略失败）。接入两处：

- `element_index` 点击路径（点击完成后）；
- 截图坐标点击路径中 AX 候选命中的分支。

### 2. sky_key 回读校验

`type_text` 的 `sky_key` 分支在投递前记录焦点元素的文本，投递后等待最多 0.5 s：

- 沿用既有策略 `keyboardTextWriteNeedsVerification`（只有空白 Web 文本控件才验证）；
- 通过 `isSecureTextField` 排除密码字段，绝不读取其数值；
- 超时仍未变化时抛出 `type_text delivered sky_key input but the focused text element did not change…`。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `docs/RELIABILITY.md`
- `docs/references/baseline-2026-11-11.md`

## 验证

- `swift test`：498 个用例，8 个实机用例按门控跳过，0 失败。
- 聚焦实测（钉钉）：先把焦点复位到消息框（`AXTextArea`）→ `click(element_index: 11)` →
  焦点变为 `AXTextField placeholder="搜索 (⌘F)"`。修复前同一步骤焦点不动。
- 端到端实测：`click` + `type_text("zq9")` → 读回 `searchValue="zq9"`、`composerValue=""`；
  `press_key escape` 后两者均为空。
- sky_key 回读实测：`type_text(zq7, key_method=sky_key)` + 3 次退格全部成功，输入框无残留、
  校验无误报。

## 已知限制

- 聚焦是 best effort：目标元素不支持可写 `AXFocused` 时不会生效。
- 回读只覆盖既有的「空白 Web 文本控件」策略范围；不扩展为对所有输入控件强制校验。
- 坐标点击路径仅在 AX 候选命中时聚焦；非 AX 回退（sky_click / app_post）不追加聚焦。
