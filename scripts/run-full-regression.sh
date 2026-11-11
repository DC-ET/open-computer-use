#!/usr/bin/env bash

# One-command local regression for open-computer-use.
#
# The GUI steps take over windows, the pointer and keyboard focus, so they are
# skipped with --skip-gui and should only run while nobody is using the Mac.
# The app matrix additionally types a marker into running apps, so it stays
# behind --include-app-matrix.
#
# Output: one log per step in a temp directory plus a JSON summary on stdout.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

skip_gui=0
include_matrix=0
stress_loops="${OPEN_COMPUTER_USE_STRESS_LOOPS:-5}"
bench_cycles="${OPEN_COMPUTER_USE_BENCH_CYCLES:-10}"

usage() {
  cat <<'USAGE'
用法: ./scripts/run-full-regression.sh [选项]

  --skip-gui             只跑无 GUI 的部分（构建、单元测试、静态检查）
  --include-app-matrix   额外跑 AppMatrix（会向运行中的 app 输入标记）
  --loops N              stress 轮数，默认 5
  --bench-cycles N       后台输入基准轮数，默认 10
  -h, --help             显示帮助

不带 --skip-gui 时会跑 smoke / stress / 实机门控 / benchmark，期间会接管
窗口、指针和键盘焦点，请确保没人正在使用这台 Mac。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-gui) skip_gui=1 ;;
    --include-app-matrix) include_matrix=1 ;;
    --loops)
      shift
      stress_loops="${1:?--loops 需要数字}"
      ;;
    --bench-cycles)
      shift
      bench_cycles="${1:?--bench-cycles 需要数字}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log_dir="$(mktemp -d "${TMPDIR:-/tmp}/ocu-full-regression.XXXXXX")"
failed_steps=""
json_steps=""
step_count=0
started_all="$(date +%s)"

run_step() {
  local name="$1"
  shift
  local log="${log_dir}/$(printf '%s' "${name}" | tr ' /:' '___').log"
  local started status seconds
  step_count=$((step_count + 1))
  printf '▶ %s\n' "${name}"
  started="$(date +%s)"
  if "$@" >"${log}" 2>&1; then
    status="ok"
  else
    status="failed"
    failed_steps="${failed_steps} ${name}"
  fi
  seconds=$(( $(date +%s) - started ))
  if [[ "${status}" == "ok" ]]; then
    printf '  ok (%ss)\n' "${seconds}"
  else
    printf '  FAILED (%ss) 日志: %s\n' "${seconds}" "${log}"
  fi
  json_steps="${json_steps}${json_steps:+,}{\"name\":\"${name}\",\"status\":\"${status}\",\"seconds\":${seconds}}"
}

run_sky_click() {
  OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests
}

run_sky_key() {
  OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests
}

run_occlusion() {
  OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests
}

run_agent_display() {
  OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_ENABLED=true OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST=1 \
    swift test --filter AgentDisplayLiveTests
}

run_cross_space() {
  OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests
}

run_stress() {
  OPEN_COMPUTER_USE_STRESS_LOOPS="${stress_loops}" ./scripts/run-tool-stress-tests.sh
}

run_benchmark() {
  OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH=1 OPEN_COMPUTER_USE_BENCH_CYCLES="${bench_cycles}" \
    swift test --filter BackgroundInputBenchmarkLiveTests
}

run_app_matrix() {
  OPEN_COMPUTER_USE_RUN_APP_MATRIX=1 OPEN_COMPUTER_USE_APP_MATRIX_PARK=1 \
    OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_ENABLED=true swift test --filter AppMatrixLiveTests
}

run_go_tests() {
  (cd apps/OpenComputerUseWindows && go test ./...) &&
    (cd apps/OpenComputerUseLinux && go test ./...) &&
    (cd apps/OpenComputerUseLinux && python3 -m unittest -v runtime_test.py)
}

run_python_tests() {
  python3 scripts/tests/locked-use-auth-latency.test.py &&
    python3 scripts/tests/locked-use-notarization.test.py &&
    python3 scripts/tests/locked-use-release-policy.test.py &&
    python3 scripts/tests/locked-use-release-packaging.test.py
}

run_repo_checks() {
  ./scripts/check-docs.sh &&
    ./scripts/check-repo-hygiene.sh &&
    ./scripts/check-action-pinning.sh
}

run_node_tests() {
  node --test scripts/node-repl/*.test.mjs scripts/tests/*.test.mjs
}

echo "== open-computer-use 全量回归 =="
echo "仓库: ${repo_root}"
echo "日志: ${log_dir}"
if [[ "${skip_gui}" == "1" ]]; then
  echo "模式: 仅无 GUI（--skip-gui）"
else
  echo "模式: 含 GUI 实机步骤（会接管窗口与输入）"
fi
echo

run_step "build" swift build
run_step "swift test" swift test
run_step "node tests" run_node_tests
run_step "python tests" run_python_tests
run_step "repo checks" run_repo_checks
if command -v go >/dev/null 2>&1; then
  run_step "go tests" run_go_tests
else
  printf '▶ %s\n  跳过：%s\n' "go tests" "未安装 go"
fi

if [[ "${skip_gui}" == "0" ]]; then
  run_step "smoke" ./scripts/run-tool-smoke-tests.sh
  run_step "stress (${stress_loops} loops)" run_stress
  run_step "sky_click live" run_sky_click
  run_step "sky_key live" run_sky_key
  run_step "occlusion live" run_occlusion
  run_step "cross-space live" run_cross_space
  run_step "agent display live" run_agent_display
  run_step "background benchmark (${bench_cycles} cycles)" run_benchmark
  if [[ "${include_matrix}" == "1" ]]; then
    run_step "app matrix" run_app_matrix
  else
    printf '▶ %s\n  跳过：%s\n' "app matrix" "需要 --include-app-matrix（会向运行中的 app 输入标记）"
  fi
fi

seconds_total=$(( $(date +%s) - started_all ))

if [[ -z "${failed_steps}" ]]; then
  ok="true"
  summary="全部 ${step_count} 个步骤通过"
else
  ok="false"
  summary="失败步骤:${failed_steps}"
fi

printf '\n%s（%ss）\n' "${summary}" "${seconds_total}"
printf '{"ok":%s,"steps":%d,"seconds":%d,"logDir":"%s","failures":"%s","results":[%s]}\n' \
  "${ok}" "${step_count}" "${seconds_total}" "${log_dir}" "${failed_steps# }" "${json_steps}"

[[ "${ok}" == "true" ]]
