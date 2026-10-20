#!/usr/bin/env bash
# Run only in the isolated, network-disabled container via verify-local.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sf plugins --core --json > "$work/plugins.json"
python3 - "$work/plugins.json" "$ROOT/test-data/assertions/scenarios.v1.json" <<'PY'
import json,sys
plugins=json.load(open(sys.argv[1])); pins=json.load(open(sys.argv[2]))['localEnginePins']
def objects(x):
    if isinstance(x,dict):
        yield x
        for v in x.values():yield from objects(v)
    elif isinstance(x,list):
        for v in x:yield from objects(v)
for name,version in pins.items():
    assert any(x.get('name')==name and x.get('version')==version for x in objects(plugins)), 'Wrong/missing plugin: '+name
PY
java -version
node "$ROOT/scripts/test-result-table.cjs"
mkdir "$work/bin" "$work/repo"
cat > "$work/bin/copado" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ "$1" == '-u' ]]; then
    jq -e '.violations | type == "array"' "$2" >/dev/null
    touch "$UPLOAD_MARKER"
fi
EOF
cat > "$work/bin/copado-git-get" <<'EOF'
#!/usr/bin/env bash
# Checkout is already prepared; Git and both sf commands remain real.
exit 0
EOF
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
export UPLOAD_MARKER="$work/uploaded"
cd "$work/repo"
git init -q
git config user.name 'Local fixture test'
git config user.email 'fixture@example.invalid'
git config commit.gpgsign false
cp "$ROOT/test-data/sfdx-project.json" .
git add sfdx-project.json
git commit -qm 'Synthetic baseline'
git update-ref refs/remotes/origin/main HEAD
cp -R "$ROOT/test-data/force-app" .
cp "$ROOT/test-data/configs/local-smoke.yaml" code-analyzer.yaml
git add force-app code-analyzer.yaml
git commit -qm 'Synthetic fixture delta'
git update-ref refs/remotes/origin/promotion/LOCAL HEAD
export branchesAndFileIdJson='{"originBranch":"promotion/LOCAL","destinationBranch":"main"}'
export targetBranch=main baseBranch= severityThreshold=2 apexGuruSessionId= apexGuruEndpoint=
export CF_COPADO_TESTING_MODE=1
code=0
bash "$ROOT/copado/functions/Run_CodeAnalyzer_QIF.sh" > "$work/function.log" 2>&1 || code=$?
# Presence is stable intent; do not pin engine-dependent violation totals.
test "$code" = 1
test -f "$work/uploaded"
test -s changed-sources/package/package.xml
jq -e '[.violations[].engine] | index("pmd") != null and index("regex") != null and index("flow") != null and index("eslint") != null' output.json >/dev/null
jq -e '.violations | any(.engine == "pmd" and .rule == "ApexCSRF" and .severity == 1)' output.json >/dev/null
jq -e '[.violations[] | select(.rule == "UnexpectedEngineError" or .rule == "UninstantiableEngineError")] | length == 0' output.json >/dev/null
python3 - <<'PY'
import json
x=json.load(open('output.json'));v=x['violations'];assert x['violationCounts']['total']==len(v)
for s in range(1,6):assert x['violationCounts']['sev'+str(s)]==sum(a['severity']==s for a in v)
assert not any(a['engine']=='apexguru' for a in v)
PY
# Verify actual CLI threshold semantics, not a mock's implementation.
mkdir "$work/old-api"
cp "$ROOT/test-data/force-app/main/default/classes/PermissionsException.cls" "$work/old-api/"
cp "$ROOT/test-data/variants/PermissionsException.api55.cls-meta.xml" "$work/old-api/PermissionsException.cls-meta.xml"
for threshold in 1 2; do
    code=0
    sf code-analyzer run --rule-selector regex --workspace "$work/old-api" --severity-threshold "$threshold" --output-file "$work/regex-$threshold.json" > "$work/regex-$threshold.log" 2>&1 || code=$?
    if [[ "$threshold" == 1 ]]; then test "$code" = 0; else test "$code" = 2; fi
    jq -e '.violations | any(.rule == "AvoidOldSalesforceApiVersions" and .severity == 2)' "$work/regex-$threshold.json" >/dev/null
done
mkdir "$work/flow-only"
cp "$ROOT/test-data/force-app/main/default/flows/TestUserDataSharingViolationExact.flow-meta.xml" "$work/flow-only/"
for threshold in 2 4; do
    code=0
    sf code-analyzer run --rule-selector flow --workspace "$work/flow-only" --severity-threshold "$threshold" --output-file "$work/flow-$threshold.json" > "$work/flow-$threshold.log" 2>&1 || code=$?
    if [[ "$threshold" == 2 ]]; then test "$code" = 0; else test "$code" = 4; fi
    jq -e '.violations | length > 0 and all(.severity == 4)' "$work/flow-$threshold.json" >/dev/null
done
echo 'Real Git delta, local engines, report upload contract, pins, and CLI thresholds passed.'
