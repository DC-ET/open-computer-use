# Drag works on web pages again

## 用户诉求

在钉钉卡片搭建器里用 `drag` 把组件拖进画布没有任何反应，但手动拖动是正常的。
要求先确认是工具的问题还是页面的问题，如果是工具就修掉。

## 根因

`drag` 默认走 `app_post`：`CGEvent.postToPid`，事件直接送进目标进程，不经过 window server。

`DragDeliveryPath` 的注释其实已经写明这条路径

> cannot drive window-server drag sessions such as window moves, text selection,
> or Finder drag-and-drop

而 HTML5 拖放（Chromium / Electron / CEF / WebKit）只认 window-server 的拖拽会话：
页面要收到 `dragstart` / `dragover` 才会接受 `drop`。所以事件发出去了、`isError: false`，
画布却什么都不动。

设 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` 后同一坐标拖拽立刻成功，
确认了判断。

## 主要改动

### 1. `method` 参数

`drag` 新增 `method`：

- `auto`（默认）：按目标选择路径
- `app_post`：强制原路径，不移动真实指针
- `global`：强制 window-server 路径

### 2. auto 的判定

新增 `appRunsWebDragAndDrop(bundleURL:)`：检查 app bundle 的
`Contents/Frameworks` 是否含 `chrom` / `electron` / `cef` / `webkit`。
命中即认为拖放运行在 web 引擎里。

`auto` 在命中时直接用 `.global`，因为这条路径下 `app_post` 100% 无效，
再让环境变量门禁拦着只会让调用方困惑。原生控件维持原行为（默认 `app_post`，
只有 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` 时才走全局）。

### 3. 结果说明

`dragDeliveryNote` 按实际路径和 `method` 给出不同说明：走全局时明确写出原因
（目标运行 web 引擎，或调用方显式要求），提醒指针可能移动、焦点可能变化。

### 4. 兼容

保留 `dragDeliveryPath(environment:)` 旧签名，等价于 `auto` + 非 web，
现有测试与调用不受影响。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DragDeliveryMethodTests.swift`

## 验证

- `swift test --filter DragDeliveryMethodTests`：5 tests，0 failures。
- Chrome + 钉钉卡片搭建器实测：不设任何环境变量，
  `drag` 从组件库把「基础文本」拖进画布，卡片新增一行文本；
  结果说明为 `Drag delivered via global pointer path: the target runs a web engine…`。
- 同一坐标在修复前（`app_post`）无任何效果。

## 已知限制

- `auto` 对 web 内容会移动真实指针并可能改变前台应用，这是 HTML5 拖放的必要代价。
  不希望指针被移动时传 `method: "app_post"`，但要接受 web 拖放不会生效。
- 判定依据是 bundle 的 Frameworks 目录，不覆盖把 web 引擎内嵌成单文件的场景。
- `drag` 仍要求先有一次带截图的 `get_app_state`，坐标来自该截图。
