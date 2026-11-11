#!/bin/bash
# SDK builds use devecocli. hdc is only used for test-HAP install / aa test,
# which the current devecocli does not expose. Never uninstall or clear app data.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:?Usage: bash scripts/test-jsonschema-device.sh DEVICE_SERIAL}"
STUDIO="${DEVECO_STUDIO_PATH:-/Applications/DevEco-Studio.app/Contents}"
HDC="${DEVECO_SDK_HOME:-$STUDIO/sdk}/default/openharmony/toolchains/hdc"
node scripts/test-jsonschema.mjs
mkdir -p docs/jsonschema
for target in default ohosTest; do
  devecocli build --modules "entry@$target" > "docs/jsonschema/build-$target.log" 2>&1
  tail -5 "docs/jsonschema/build-$target.log"
  "$HDC" -t "$TARGET" install "entry/build/default/outputs/$target/entry-$target-signed.hap"
done
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
"$HDC" -t "$TARGET" shell aa test -b com.dalton.dashiell -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class 'JsonSchemaExpansionFixtures,JsonSchemaExpansion' \
  -s timeout 60000 | tee "$LOG"
python3 - "$LOG" "$TARGET" <<'PY'
import re,sys,json,pathlib
text=pathlib.Path(sys.argv[1]).read_text()
pathlib.Path('docs/jsonschema/device-test.log').write_text(text)
expected=json.loads(pathlib.Path('docs/jsonschema/host-results.json').read_text())['tests']
match=re.search(r'Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+), Ignore: (\d+)',text)
if not match or tuple(map(int,match.groups())) != (expected,0,0,expected,0):
    raise SystemExit('FAILED: missing, failed or incomplete device test results')
if 'TestFinished-ResultCode: 0' not in text:
    raise SystemExit('FAILED: no successful test completion')
pathlib.Path('docs/jsonschema/device-results.json').write_text(json.dumps({
    'runner':'Hypium on HarmonyOS', 'device':sys.argv[2],
    'tests':expected, 'passed':expected, 'failed':0, 'ignored':0
},indent=2)+'\n')
print(f'PASS: {expected} schema tests executed on HarmonyOS')
PY
