# Element identity read failures on TextEdit

## 用户诉求

上一批验证时发现：对 TextEdit 的文本区先 `get_app_state` 再 `set_value`，会返回

```
element 2 no longer has the identity the snapshot showed, or could not be checked
```

即使在同一进程的 `--calls` 序列里也一样。要求查清原因。

## 根因

`ElementIdentity.read` 用 `AXUIElementCopyMultipleAttributeValues` 一次读五个属性。
TextEdit 的 `AXTextArea` 对 `AXDescription` 返回 `AXValue(.axError, -25200)`，
即 `kAXErrorFailure`。

原实现只把 `attributeUnsupported` 和 `noValue` 当作"该属性无值"，其他错误一律
`return nil`，于是整次身份读取被判失败，动作被拦下，提示语还写成"身份变了"，
掩盖了真实原因。

两个问题叠加：

1. 容忍的错误集合太窄，TextEdit 这种"描述属性读不到但控件本身稳定"的情况被误判；
2. 失败提示把"读不到"和"身份变了"合并成一句话，无法定位。

## 主要改动

### 1. 按属性区分容忍度

新增 `ElementIdentity.identityAttributeAbsenceIsTolerable(_:attribute:)`：

- `AXRole` / `AXSubrole`：只接受 `noValue` / `attributeUnsupported`。
  这两个属性决定控件是什么、以及是不是密码框，读不到时不能猜。
- `AXTitle` / `AXDescription` / `AXIdentifier`：额外接受 `failure`。
  它们只是让比较更精确，读不到就当作无值。

`cannotComplete`、`invalidUIElement` 仍然整体失败：前者通常是 app 忙，应该重试
而不是记成"无值"；后者说明元素已失效。

### 2. 失败提示分开

`ElementIdentity.validate` 现在区分两种失败：

- 读不回来：`element N: the snapshot's control (AXTextArea) could not be read back for the identity check`
- 身份变了：`element N no longer has the identity the snapshot showed (was AXTextArea "x", now AXButton "y")`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ElementIdentity.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/ElementIdentityAttributeTests.swift`

## 验证

- `swift test`：491 tests，13 skipped，0 failures。
- Node 测试：61 tests，0 failures。
- `make check-repo` 通过。
- TextEdit（macOS 26）实测：
  - `get_app_state` 后 `set_value(element_index 2, "hello")` → `isError: false`。
  - 同一索引 `set_value("")` 清空 → `isError: false`，读回为空。
  - 修复前同一操作返回上述身份错误。

## 已知限制

- 描述性属性读失败被忽略后，identity 的区分力会略降；精确性仍由快照里的
  `AXUIElement` 引用本身保证，identity 只是二次确认。
- `failure` 对 role/subrole 仍然严格失败，未放宽。
- 没做 app 级白名单：任何 app 的描述属性报 `failure` 都按无值处理。
