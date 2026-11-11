# 修复实测基线暴露的测试基础设施问题

## 用户诉求

在 `open-computer-use` 上做大量实测、验证、优化与迭代，先跑一轮完整基线。
基线暴露出三个会妨碍持续实测的问题，要求先修测试基础设施。

## 根因

1. **`make stress` 在系统 bash 下必崩**：`scripts/run-tool-stress-tests.sh` 的
   `swift build "${build_args[@]}"` 在 `set -u` 下展开空数组，macOS 自带 bash 3.2 报
   `build_args[@]: unbound variable`。默认 `debug` 配置的 `build_args` 恰好为空，所以
   `make stress` 完全不可用；`release` 配置因为数组非空才能绕过。
2. **Occlusion 实机测试首跑偶发失败**：拿到窗口后立刻调
   `NSRunningApplication(processIdentifier:)`，LaunchServices 的注册可能滞后几十毫秒，
   于是返回 nil，被当成 `Chrome is not a running application`。
3. **AppMatrix 把环境噪声当成产品失败**：没有 on-screen 窗口的 app（如全部窗口最小化的
   TextMate、窗口模型特殊的微信）仍然尝试 snapshot，必然报 `cgWindowNotFound`；
   同时指针断言用浮点精确相等，虚拟屏创建/销毁带来的亚像素坐标缩放也会误报。

## 主要改动

### 1. stress 脚本兼容 bash 3.2

沿用 `a632ca7`（keychain 空数组）的同一写法，只在数组非空时展开：

```bash
swift build ${build_args[@]+"${build_args[@]}"}
```

### 2. Occlusion 测试等待 LaunchServices 注册

新增 `waitForRunningApplication(pid:timeout:)`，50 ms 轮询、默认 3 s 超时，
替换原来的一次性查询；超时仍以 `ComputerUseError.message` 失败，不吞错。

### 3. AppMatrix 先过滤无窗口 app

新增 `hasOnScreenWindow(pid:)`：用 `CGWindowListCopyWindowInfo(.optionAll)` 按 pid
匹配 `kCGWindowIsOnscreen == true`。没有 on-screen 窗口的 app 记一行
`no on-screen window; skipped` 后跳过，不再产生 `cgWindowNotFound` 噪声。

### 4. AppMatrix 指针断言改为 1 pt 容差

`NSEvent.mouseLocation` 在虚拟屏创建/销毁后会因显示缩放产生亚像素变化
（实测 0.24 pt），精确相等必然误报。改为 `accuracy: 1`，仍能抓到真实的指针移动
（基线首次运行时的 46 pt 位移会被判定失败）。

## 受影响文件

- `scripts/run-tool-stress-tests.sh`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OcclusionKeepAliveLiveTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AppMatrixLiveTests.swift`

## 验证

- `OPEN_COMPUTER_USE_STRESS_LOOPS=2 ./scripts/run-tool-stress-tests.sh`（系统 bash 3.2）：
  `ok: true`，`fixtureOperations: 20`，`cursorIdleSmoke: 1`，10 s。
- `OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests`：
  通过，9.33 s。
- `OPEN_COMPUTER_USE_RUN_APP_MATRIX=1 OPEN_COMPUTER_USE_APP_MATRIX_PARK=1 ... swift test --filter AppMatrixLiveTests`
  （4 个 app 的精简组合）：0 失败，15.96 s；TextMate 输出
  `no on-screen window; skipped`，不再报 snapshot 失败。
- `swift test`：496 个用例，8 个实机用例按门控跳过，0 失败。
- `bash -n` / `check-repo-hygiene` / `check-docs`：通过。

## 已知限制

- 基线首次运行时的 46 pt 指针位移仍未定性，需要在无人值守时复现，区分用户操作与
  PARK/虚拟屏副作用；本次 0.24 pt 已确认是缩放噪声。
- 跨 Space 实机门控的确定性失败尚未修复，需要先定性
  `SLSManagedDisplaySetCurrentSpace` 在 macOS 26.6.2 上是否真正切换 Desktop。
- AppMatrix 中 Chrome / 语雀 / 钉钉的 `typed=false` 仍是待复现项，需要在非 PARK 模式做对照。
