#!/bin/bash
# Builds and installs main/test HAPs without uninstalling or clearing application data.
set -euo pipefail
cd "$(dirname "$0")/.."
STUDIO="${DEVECO_STUDIO_PATH:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$STUDIO/sdk}"
export JAVA_HOME="${JAVA_HOME:-$STUDIO/jbr/Contents/Home}"
export PATH="$STUDIO/tools/node/bin:$JAVA_HOME/bin:$PATH"
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
TARGET="${1:?Usage: bash scripts/test-abogus-device.sh DEVICE_SERIAL}"
mkdir -p docs/abogus
# 前置：设备用例数量要和主机侧结果对齐，而那份结果需要仓库外的 Kotlin 参考源码才能生成。
# 先在这里失败，不要花几分钟构建完才报 FileNotFoundError。
if [ ! -f docs/abogus/reference-results.json ]; then
  echo "缺少 docs/abogus/reference-results.json。" >&2
  echo "先跑一次主机侧生成（Kotlin 参考源码不在仓库内，需自备）：" >&2
  echo "  KOTLIN_DOUYIN_SOURCE=<Kotlin SDK 目录> node scripts/test-abogus.mjs" >&2
  exit 1
fi
for target in default ohosTest; do
  node "$STUDIO/tools/hvigor/bin/hvigorw.js" --mode module \
    -p "module=entry@$target" -p product=default -p requiredDeviceType=wearable \
    assembleHap --no-daemon
  "$HDC" -t "$TARGET" install "entry/build/default/outputs/$target/entry-$target-signed.hap"
done
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
"$HDC" -t "$TARGET" shell aa test -b com.dalton.dashiell -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class 'ABogusKotlinParity' \
  -s timeout 60000 | tee "$LOG"
# aa/hdc exit status alone does not prove assertion success. Check totals as well.
python3 - "$LOG" <<'PY'
import re,sys,json,pathlib
text=pathlib.Path(sys.argv[1]).read_text()
expected=json.loads(pathlib.Path('docs/abogus/reference-results.json').read_text())['count']+1
match=re.search(r'Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+), Ignore: (\d+)',text)
if not match or tuple(map(int,match.groups())) != (expected,0,0,expected,0):
    raise SystemExit('FAILED: missing, failed or incomplete device test results')
if 'TestFinished-ResultCode: 0' not in text:
    raise SystemExit('FAILED: no successful test completion')
pathlib.Path('docs/abogus/device-test.log').write_text(text)
print(f'PASS: {expected} tests executed on HarmonyOS device')
PY
