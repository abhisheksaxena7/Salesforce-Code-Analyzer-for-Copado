#!/bin/bash
set -euo pipefail

localDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
copadoDir=$(cd "$localDir/.." && pwd)

export CF_SF_ENDPOINT=https://copado.example
export CF_SF_SESSIONID=dummy
export CF_RESULTID=dummy
export CF_COPADO_TESTING_MODE=1
export branchesAndFileIdJson='{"originBranch":"promotion/P10","destinationBranch":"master"}'
export targetBranch=master
export baseBranch=
export severityThreshold=2
export git_json='{"type":"file","url":"file:///tmp/not-used-by-test"}'

testRoot=$(mktemp -d "${TMPDIR:-/tmp}/sfdx-scanner-test.XXXXXX")
trap 'rm -rf "$testRoot"' EXIT
mockBin="$testRoot/bin"
mkdir -p "$mockBin"

cat > "$mockBin/copado-git-get" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$mockBin/git" <<'EOF'
#!/bin/bash
printf 'git:%s\n' "$*" >> "${SF_CALL_LOG}"
echo "0000000000000000000000000000000000000000"
EOF

cat > "$mockBin/copado" <<'EOF'
#!/bin/bash
echo "copado $*"
exit 0
EOF

cat > "$mockBin/sf" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "${SF_CALL_LOG:?}"

if [[ "$1 $2 $3" == "sgd source delta" ]]; then
    mkdir -p changed-sources/package
    cat > changed-sources/package/package.xml <<'XML'
<Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>68.0</version></Package>
XML
    if [[ "${MOCK_DELTA_KIND:-cls}" == "cls" || "${MOCK_DELTA_KIND:-cls}" == "both" ]]; then
        mkdir -p changed-sources/force-app/main/default/classes
        cat > changed-sources/force-app/main/default/classes/ApexGuruFixture.cls <<'APEX'
public class ApexGuruFixture {
    public static void inefficient() {
        for (Account record : [SELECT Id FROM Account]) {
            Schema.getGlobalDescribe();
        }
    }
}
APEX
    fi
    if [[ "${MOCK_DELTA_KIND:-cls}" == "trigger" || "${MOCK_DELTA_KIND:-cls}" == "both" ]]; then
        mkdir -p changed-sources/force-app/main/default/triggers
        cat > changed-sources/force-app/main/default/triggers/AccountTrigger.trigger <<'APEX'
trigger AccountTrigger on Account (before insert) {
    for (Account record : Trigger.new) {
        Schema.getGlobalDescribe();
    }
}
APEX
    fi
    if [[ "${MOCK_DELTA_KIND:-cls}" == "lwc" ]]; then
        mkdir -p changed-sources/force-app/main/default/lwc/demo
        cat > changed-sources/force-app/main/default/lwc/demo/demo.js <<'JS'
export default class Demo {}
JS
    fi
    if [[ "${MOCK_DELTA_KIND:-cls}" == "destructive" ]]; then
        mkdir -p changed-sources/destructiveChanges
        cat > changed-sources/destructiveChanges/destructiveChanges.xml <<'XML'
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types><members>DeletedClass</members><name>ApexClass</name></types>
  <version>68.0</version>
</Package>
XML
    fi
    exit 0
fi

if [[ "$1 $2" == "config set" ]]; then
    if [[ "${MOCK_AUTH_FAIL:-0}" == "1" ]]; then
        if [[ -n "${MOCK_AUTH_ERR_MSG:-}" ]]; then
            printf '%s\n' "$MOCK_AUTH_ERR_MSG" >&2
        fi
        exit 1
    fi
    exit 0
fi

if [[ "$1 $2" == "code-analyzer run" ]]; then
    outputFile=
    selector=
    targetArgs=
    threshold=2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --severity-threshold)
                threshold="$2"
                shift 2
                ;;
            --output-file)
                outputFile="$2"
                shift 2
                ;;
            --rule-selector)
                selector="$selector $2"
                shift 2
                ;;
            --target)
                targetArgs="$targetArgs $2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    printf '%s\n' "SELECTOR:$selector" >> "${SF_CALL_LOG}"
    printf '%s\n' "TARGETS:$targetArgs" >> "${SF_CALL_LOG}"

    if [[ "$selector" == *"apexguru"* ]]; then
        if [[ -n "${MOCK_APEXGURU_STDERR:-}" ]]; then
            printf '%s\n' "$MOCK_APEXGURU_STDERR" >&2
        fi
        case "${MOCK_APEXGURU_STATUS:-completed}" in
            skipped)
                cat > "$outputFile" <<JSON
{
  "runDir": ".",
  "violationCounts": {"total": 0, "sev1": 0, "sev2": 0, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"apexguru": "0.43.0"},
  "violations": [],
  "insights": {
    "apexguru": {
      "status": "skipped",
      "error": {
        "code": "ORG_NOT_ELIGIBLE",
        "message": "${MOCK_APEXGURU_ERROR_MSG:-}"
      }
    }
  }
}
JSON
                ;;
            no-output)
                ;;
            engine-error|uninstantiable-error)
                if [[ "${MOCK_APEXGURU_STATUS}" == "engine-error" ]]; then
                    errorRule="UnexpectedEngineError"
                else
                    errorRule="UninstantiableEngineError"
                fi
                cat > "$outputFile" <<JSON
{
  "runDir": ".",
  "violationCounts": {"total": 1, "sev1": 1, "sev2": 0, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"apexguru": "0.43.0"},
  "violations": [{
    "rule": "$errorRule",
    "engine": "apexguru",
    "severity": 1,
    "message": "${MOCK_APEXGURU_ERROR_MSG:-ApexGuru failed}",
    "tags": [],
    "locations": []
  }]
}
JSON
                ;;
            clean)
                cat > "$outputFile" <<'JSON'
{
  "runDir": ".",
  "violationCounts": {"total": 0, "sev1": 0, "sev2": 0, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"apexguru": "0.43.0"},
  "violations": [],
  "insights": {"apexguru":{"status":"completed"}}
}
JSON
                ;;
            bad-violations)
                cat > "$outputFile" <<'JSON'
{
  "insights": {"apexguru": {"status": "completed"}},
  "violations": "bad"
}
JSON
                ;;
            merge-fail)
                cat > "$outputFile" <<'JSON'
{
  "runDir": ".",
  "violationCounts": {"total": 1, "sev1": 0, "sev2": 1, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"apexguru": "0.43.0"},
  "violations": ["not-an-object-element"],
  "insights": {"apexguru": {"status": "completed"}}
}
JSON
                ;;
            *)
                cat > "$outputFile" <<'JSON'
{
  "runDir": ".",
  "violationCounts": {"total": 1, "sev1": 0, "sev2": 1, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"apexguru": "0.43.0"},
  "violations": [{"rule":"InefficientSchemaCall","engine":"apexguru","severity":2,"tags":["Performance"],"locations":[]}],
  "insights": {"apexguru":{"status":"completed"}}
}
JSON
                ;;
        esac
        if [[ -f "$outputFile" && -n "${MOCK_APEXGURU_ANALYSIS_MODE:-}" ]]; then
            jq --arg mode "$MOCK_APEXGURU_ANALYSIS_MODE" '.insights.apexguru.analysisMode = $mode' "$outputFile" > "$outputFile.tmp"
            mv "$outputFile.tmp" "$outputFile"
        fi
        exit "${MOCK_APEXGURU_EXIT_CODE:-0}"
    else
        if [[ -n "${MOCK_LOCAL_STDERR:-}" ]]; then
            printf '%s\n' "$MOCK_LOCAL_STDERR" >&2
        fi
        case "${MOCK_LOCAL_STATUS:-violation}" in
            no-output)
                ;;
            corrupt)
                printf '%s\n' '{not valid json' > "$outputFile"
                ;;
            clean)
                cat > "$outputFile" <<'JSON'
{
  "runDir": ".",
  "violationCounts": {"total": 0, "sev1": 0, "sev2": 0, "sev3": 0, "sev4": 0, "sev5": 0},
  "versions": {"pmd": "7"},
  "violations": []
}
JSON
                ;;
            *)
                cat > "$outputFile" <<'JSON'
{
  "runDir": ".",
  "violationCounts": {"total": 1, "sev1": 0, "sev2": 0, "sev3": 1, "sev4": 0, "sev5": 0},
  "versions": {"pmd": "7"},
  "violations": [{"rule":"LocalRule","engine":"pmd","severity":3,"tags":[],"locations":[]}]
}
JSON
                ;;
        esac
        if [[ -n "${MOCK_LOCAL_SEVERITY:-}" ]]; then
            jq --argjson severity "$MOCK_LOCAL_SEVERITY" '.violations |= map(.severity = $severity) | .violationCounts = {total:1,sev1:0,sev2:0,sev3:0,sev4:0,sev5:0} | .violationCounts["sev" + ($severity|tostring)] = 1' "$outputFile" > "$outputFile.tmp"
            mv "$outputFile.tmp" "$outputFile"
        fi
        if [[ "${MOCK_AUTO_THRESHOLD:-0}" == 1 ]]; then
            exit "$(jq --argjson threshold "$threshold" '[.violations[].severity | select(. <= $threshold)] | min // 0' "$outputFile")"
        fi
        exit "${MOCK_LOCAL_EXIT_CODE:-0}"
    fi
fi

echo "Unexpected sf command: $*" >&2
exit 1
EOF

chmod +x "$mockBin/copado" "$mockBin/copado-git-get" "$mockBin/git" "$mockBin/sf"
export PATH="$mockBin:$localDir:$PATH"

run_case() {
    local caseName="$1"
    local sessionId="$2"
    local expectedCount="$3"
    local expectedApexGuruCount="$4"
    local endpointOverride="${5:-}"
    local deltaKind="${6:-cls}"
    local configContent="${7:-}"
    local configFileName="${8:-code-analyzer.yaml}"
    local expectedExitCode="${9:-0}"
    local workDir="$testRoot/$caseName"

    rm -rf "$workDir"
    mkdir -p "$workDir"
    cd "$workDir"
    if [[ -n "$configContent" ]]; then
        printf '%s\n' "$configContent" > "$configFileName"
    fi

    export SF_CALL_LOG="$workDir/sf-calls.log"
    : > "$SF_CALL_LOG"
    export MOCK_DELTA_KIND="$deltaKind"
    export apexGuruSessionId="$sessionId"
    export apexGuruEndpoint="$endpointOverride"
    unset ruleSelector
    if [[ -z "$apexGuruEndpoint" && -n "$sessionId" && ! "$sessionId" =~ ^\{\$ ]]; then
        apexGuruEndpoint="https://example.my.salesforce.com/services/Soap/u/68.0"
    fi

    local actualExitCode=0
    bash "$copadoDir/functions/Run_CodeAnalyzer_QIF.sh" > function.log 2>&1 || actualExitCode=$?
    test "$actualExitCode" = "$expectedExitCode"

    test "$(jq -r '.violationCounts.total' output.json)" = "$expectedCount"
    test "$(jq '[.violations[] | select(.engine == "apexguru")] | length' output.json)" = "$expectedApexGuruCount"
    if [[ -n "$sessionId" ]]; then
        ! grep -F -q "$sessionId" function.log
    fi

    local localSelectorLine
    localSelectorLine=$(grep '^SELECTOR:' "$SF_CALL_LOG" | head -n 1 || true)
    if [[ -n "$localSelectorLine" && "${expectedCount}" != "$expectedApexGuruCount" ]]; then
        [[ "$localSelectorLine" != *apexguru* ]]
    fi
}

# 1. Missing credentials -> ApexGuru skipped, local report preserved.
run_case apexguru-skipped "" 1 0
grep -q "no source-environment credential" "$testRoot/apexguru-skipped/function.log"

# 2. Unresolved Copado dynamic expressions -> treated as missing credentials.
run_case apexguru-unresolved '{$Source.Credential.SessionId}' 1 0 '{$Source.Credential.Endpoint}'
grep -q "no source-environment credential" "$testRoot/apexguru-unresolved/function.log"
! grep -q "org-instance-url" "$testRoot/apexguru-unresolved/sf-calls.log"

# 3. Apex class delta -> ApexGuru runs with .cls target and merges output.
run_case apexguru-merged "test-access-token" 2 1
grep -q -- "--target-org test-access-token" "$testRoot/apexguru-merged/sf-calls.log"
grep -q "org-instance-url=https://example.my.salesforce.com$" "$testRoot/apexguru-merged/sf-calls.log"
! grep -q "services/Soap" "$testRoot/apexguru-merged/sf-calls.log"
grep -q "Running ApexGuru on changed Apex classes and triggers" "$testRoot/apexguru-merged/function.log"
grep -qF -- '--target ./changed-sources/**/*.cls' "$testRoot/apexguru-merged/sf-calls.log"
! grep -qF -- '--target ./changed-sources/**/*.trigger' "$testRoot/apexguru-merged/sf-calls.log"

# 4. Trigger-only delta -> ApexGuru runs with .trigger target only.
run_case apexguru-trigger-only "test-access-token" 2 1 "" trigger
grep -q "Running ApexGuru on changed Apex classes and triggers" "$testRoot/apexguru-trigger-only/function.log"
grep -qF -- '--target ./changed-sources/**/*.trigger' "$testRoot/apexguru-trigger-only/sf-calls.log"
! grep -qF -- '--target ./changed-sources/**/*.cls' "$testRoot/apexguru-trigger-only/sf-calls.log"

# 5. Both .cls and .trigger in delta -> ApexGuru runs with both target globs.
run_case apexguru-both-cls-and-trigger "test-access-token" 2 1 "" both
grep -q "ApexGuru target args: --target ./changed-sources/\*\*/\*.cls --target ./changed-sources/\*\*/\*.trigger" "$testRoot/apexguru-both-cls-and-trigger/function.log"
grep -qF -- '--target ./changed-sources/**/*.cls' "$testRoot/apexguru-both-cls-and-trigger/sf-calls.log"
grep -qF -- '--target ./changed-sources/**/*.trigger' "$testRoot/apexguru-both-cls-and-trigger/sf-calls.log"

# 6. Non-Apex change (e.g. LWC only) -> Local pass runs, ApexGuru skipped with updated message.
run_case apexguru-no-apex "test-access-token" 1 0 "" lwc
grep -q "no Apex classes or triggers" "$testRoot/apexguru-no-apex/function.log"

# 7. Scenario: Trying to skip ApexGuru in an org that HAS it (via code-analyzer.yaml and code-analyzer.yml).
run_case skip-apexguru-in-eligible-org-yaml "test-access-token" 1 0 "" cls $'engines:\n  apexguru:\n    disable_engine: true' "code-analyzer.yaml"
grep -q "disabled in the Code Analyzer configuration" "$testRoot/skip-apexguru-in-eligible-org-yaml/function.log"
! grep -q -- "--rule-selector apexguru" "$testRoot/skip-apexguru-in-eligible-org-yaml/sf-calls.log"

run_case skip-apexguru-in-eligible-org-yml "test-access-token" 1 0 "" cls $'engines:\n  apexguru:\n    disable_engine: true' "code-analyzer.yml"
grep -q "disabled in the Code Analyzer configuration" "$testRoot/skip-apexguru-in-eligible-org-yml/function.log"
! grep -q -- "--rule-selector apexguru" "$testRoot/skip-apexguru-in-eligible-org-yml/sf-calls.log"

# 8. Scenario: Trying to force run ApexGuru in an org that DOES NOT have it (via code-analyzer.yaml).
# 8a. Org connected, but org does not have ApexGuru enabled/authorized (returns status: skipped + error message).
export MOCK_APEXGURU_STATUS=skipped
export MOCK_APEXGURU_EXIT_CODE=2
export MOCK_APEXGURU_ERROR_MSG="ApexGuru is not enabled for org session test-access-token (401 Unauthorized) $(printf 'x%.0s' {1..240})"
run_case force-apexguru-org-not-enabled "test-access-token" 1 0 "" cls $'engines:\n  apexguru:\n    disable_engine: false' "code-analyzer.yaml" 0
grep -q "did not complete remote analysis" "$testRoot/force-apexguru-org-not-enabled/function.log"
grep -q "ApexGuru is not enabled for org session \[redacted\]" "$testRoot/force-apexguru-org-not-enabled/function.log"
warningProgress=$(grep '^copado -p ApexGuru was skipped' "$testRoot/force-apexguru-org-not-enabled/function.log" | sed 's/^copado -p //')
test "${#warningProgress}" -le 240
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_EXIT_CODE MOCK_APEXGURU_ERROR_MSG

# 8b. Force-enabled in code-analyzer.yaml, but no org credential exists in the environment.
run_case force-apexguru-no-credential "" 1 0 "" cls $'engines:\n  apexguru:\n    disable_engine: false' "code-analyzer.yaml" 0
grep -q "no source-environment credential" "$testRoot/force-apexguru-no-credential/function.log"

# 9. Scenario: Trying to skip SOME engines via code-analyzer.yaml.
run_case skip-some-engines-yaml "test-access-token" 2 1 "" cls $'engines:\n  sfge:\n    disable_engine: true\n  cpd:\n    disable_engine: true\n  flow:\n    disable_engine: true' "code-analyzer.yaml"
localLine=$(grep '^SELECTOR:' "$testRoot/skip-some-engines-yaml/sf-calls.log" | head -n 1)
[[ "$localLine" != *sfge* && "$localLine" != *cpd* && "$localLine" != *flow* && "$localLine" != *apexguru* ]]
[[ "$localLine" == *pmd* && "$localLine" == *eslint* && "$localLine" == *uibundle* ]]

# 10. Scenario: Trying to skip ALL other engines and JUST run ApexGuru via code-analyzer.yaml.
allLocalDisabledYaml=$'engines:\n  cpd:\n    disable_engine: true\n  eslint:\n    disable_engine: true\n  flow:\n    disable_engine: true\n  pmd:\n    disable_engine: true\n  regex:\n    disable_engine: true\n  retire-js:\n    disable_engine: true\n  sfge:\n    disable_engine: true\n  uibundle:\n    disable_engine: true\n  apexguru:\n    disable_engine: false'
run_case only-apexguru-via-yaml "test-access-token" 1 1 "" cls "$allLocalDisabledYaml" "code-analyzer.yaml"
test "$(grep -c '^SELECTOR:' "$testRoot/only-apexguru-via-yaml/sf-calls.log")" = "1"
grep -q '^SELECTOR: apexguru$' "$testRoot/only-apexguru-via-yaml/sf-calls.log"

# 11. Scenario: No violations (clean local + clean ApexGuru, and empty delta directory).
export MOCK_LOCAL_STATUS=clean
export MOCK_APEXGURU_STATUS=clean
run_case no-violations-clean-scan "test-access-token" 0 0 "" both $'engines:\n  apexguru:\n    disable_engine: false' "code-analyzer.yaml" 0
test "$(jq -r '.violationCounts.sev1 + .violationCounts.sev2 + .violationCounts.sev3 + .violationCounts.sev4 + .violationCounts.sev5' "$testRoot/no-violations-clean-scan/output.json")" = "0"
test "$(jq '.violations | length' "$testRoot/no-violations-clean-scan/output.json")" = "0"
unset MOCK_LOCAL_STATUS MOCK_APEXGURU_STATUS

run_case no-violations-empty-delta "" 0 0 "" none "" "code-analyzer.yaml" 0
! grep -q '^SELECTOR:' "$testRoot/no-violations-empty-delta/sf-calls.log"

# 12. Branch context, severityThreshold fallback, plugin-missing fallback, malformed YAML, auth failure, and stderr fallback coverage.
# 12a. Feature branch context + invalid severityThreshold + malformed code-analyzer.yaml + plugin fallback + bare endpoint + auth failure with & without reason.
export branchesAndFileIdJson='{"originBranch":"feature/US-001","destinationBranch":"main"}'
export targetBranch=
export baseBranch=develop
export severityThreshold="invalid"
export CODE_ANALYZER_PLUGIN_DIR="$testRoot/nonexistent-plugin"
export MOCK_AUTH_FAIL=1
export MOCK_AUTH_ERR_MSG="Authentication failed for token 00Dxx0000001gPFEAY!AQ8AQH_secret_token"
run_case feature-context-auth-fail "test-access-token" 1 0 "example.my.salesforce.com" cls "" "code-analyzer.yaml" 0
grep -q "In feature context, using baseBranch as the destinationBranch." "$testRoot/feature-context-auth-fail/function.log"
grep -q "Local rule selectors: --rule-selector all --rule-selector uibundle" "$testRoot/feature-context-auth-fail/function.log"
grep -q "org-instance-url=example.my.salesforce.com$" "$testRoot/feature-context-auth-fail/sf-calls.log"
grep -q "could not be authenticated. Authentication failed for token \[redacted\]" "$testRoot/feature-context-auth-fail/function.log"

export MOCK_AUTH_ERR_MSG=""
run_case auth-fail-empty-reason "test-access-token" 1 0 "example.my.salesforce.com" cls "" "code-analyzer.yaml" 0
grep -q "could not be authenticated.$" "$testRoot/auth-fail-empty-reason/function.log"
unset MOCK_AUTH_FAIL MOCK_AUTH_ERR_MSG CODE_ANALYZER_PLUGIN_DIR

# 12b. Unclear branch context + malformed YAML + missing local-output.json + ApexGuru non-zero exit & stderr tail fallback.
export branchesAndFileIdJson='{"originBranch":"hotfix/H1","destinationBranch":"release"}'
export targetBranch=
export baseBranch=
export severityThreshold=2
export MOCK_LOCAL_STATUS=no-output
export MOCK_LOCAL_STDERR="Error (2): Threshold exceeded"
export MOCK_APEXGURU_EXIT_CODE=2
run_case unclear-context-apexguru-exit "test-access-token" 1 1 "" cls ": : invalid yaml : [" "code-analyzer.yaml" 1
grep -q "Context unclear, using destinationBranch from branchesAndFileIdJson" "$testRoot/unclear-context-apexguru-exit/function.log"
grep -q "copado -p Writing to result -e Threshold exceeded" "$testRoot/unclear-context-apexguru-exit/function.log"
unset MOCK_LOCAL_STATUS MOCK_LOCAL_STDERR MOCK_APEXGURU_EXIT_CODE

# 12c. ApexGuru fails without output file: stderr keyword match, stderr tail fallback, and empty stderr.
export MOCK_APEXGURU_STATUS=no-output
export MOCK_APEXGURU_STDERR="Fatal error connecting to remote service"
run_case apexguru-stderr-keyword "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q "did not complete remote analysis. Fatal error connecting to remote service" "$testRoot/apexguru-stderr-keyword/function.log"

export MOCK_APEXGURU_STDERR="Remote service unavailable right now"
run_case apexguru-stderr-tail "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q "did not complete remote analysis. Remote service unavailable right now" "$testRoot/apexguru-stderr-tail/function.log"

export MOCK_APEXGURU_STDERR=""
run_case apexguru-stderr-empty "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q "did not complete remote analysis.$" "$testRoot/apexguru-stderr-empty/function.log"
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_STDERR

# 13. Additional pre-commit edge cases.
# 13a. Delete-only delta -> package manifests are not treated as scannable source.
run_case destructive-only-delta "" 0 0 "" destructive "" "code-analyzer.yaml" 0
! grep -q '^SELECTOR:' "$testRoot/destructive-only-delta/sf-calls.log"
grep -q "no Apex classes or triggers" "$testRoot/destructive-only-delta/function.log"

# 13b. Engine error violations -> ApexGuru output is rejected and its reason is redacted.
for engineErrorStatus in engine-error uninstantiable-error; do
    export MOCK_APEXGURU_STATUS="$engineErrorStatus"
    export MOCK_APEXGURU_EXIT_CODE=1
    export MOCK_APEXGURU_ERROR_MSG="ApexGuru engine failed for session test-access-token"
    run_case "apexguru-$engineErrorStatus" "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
    grep -q "did not complete remote analysis. ApexGuru engine failed for session \[redacted\]" \
        "$testRoot/apexguru-$engineErrorStatus/function.log"
    ! jq -e '.violations[] | select(.rule == "UnexpectedEngineError" or .rule == "UninstantiableEngineError")' \
        "$testRoot/apexguru-$engineErrorStatus/output.json" >/dev/null
done
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_EXIT_CODE MOCK_APEXGURU_ERROR_MSG

# 13c. A skipped ApexGuru Error (...) line must not become the Copado result error.
export MOCK_APEXGURU_STATUS=skipped
export MOCK_APEXGURU_EXIT_CODE=1
export MOCK_APEXGURU_STDERR="Error (1): Remote failure for session test-access-token"
run_case apexguru-skipped-error-isolation "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q '^copado -p Writing to result -e $' "$testRoot/apexguru-skipped-error-isolation/function.log"
! grep -F -q "test-access-token" "$testRoot/apexguru-skipped-error-isolation/function.log"
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_EXIT_CODE MOCK_APEXGURU_STDERR

# 13d. When both passes exceed the threshold, return the most severe (lowest) exit code.
export MOCK_LOCAL_EXIT_CODE=3
export MOCK_LOCAL_STDERR="Error (3): Local threshold exceeded"
export MOCK_APEXGURU_EXIT_CODE=2
export MOCK_APEXGURU_STDERR="Error (2): ApexGuru threshold exceeded"
run_case dual-threshold-exit-precedence "test-access-token" 2 1 "" cls "" "code-analyzer.yaml" 2
test "$(jq -r '.violationCounts.sev2' "$testRoot/dual-threshold-exit-precedence/output.json")" = "1"
test "$(jq -r '.violationCounts.sev3' "$testRoot/dual-threshold-exit-precedence/output.json")" = "1"
grep -q '^copado -p Writing to result -e Local threshold exceeded ApexGuru threshold exceeded$' \
    "$testRoot/dual-threshold-exit-precedence/function.log"
unset MOCK_LOCAL_EXIT_CODE MOCK_LOCAL_STDERR MOCK_APEXGURU_EXIT_CODE MOCK_APEXGURU_STDERR

# 13e. Asymmetric credentials skip safely; endpoint normalization retains port and drops path/query.
run_case unresolved-endpoint "test-access-token" 1 0 '{$Source.Credential.Endpoint}' cls "" "code-analyzer.yaml" 0
grep -q "no source-environment credential" "$testRoot/unresolved-endpoint/function.log"
! grep -q "org-instance-url" "$testRoot/unresolved-endpoint/sf-calls.log"

run_case complex-endpoint "test-access-token" 2 1 \
    "https://example.my.salesforce.com:8443/services/Soap/u/68.0?orgId=00Dxx" cls "" "code-analyzer.yaml" 0
grep -q "org-instance-url=https://example.my.salesforce.com:8443$" "$testRoot/complex-endpoint/sf-calls.log"
! grep -q "services/Soap" "$testRoot/complex-endpoint/sf-calls.log"

# 13f. Corrupt or missing local output after an attempted scan fails the gate and uploads a valid empty placeholder.
export MOCK_LOCAL_STATUS=corrupt
run_case corrupt-local-output "" 0 0 "" cls "" "code-analyzer.yaml" 1
grep -q '^copado -p Writing to result -e Local Code Analyzer did not produce a valid report\.$' \
    "$testRoot/corrupt-local-output/function.log"
jq -e '
    .runDir == "."
    and .violationCounts == {total: 0, sev1: 0, sev2: 0, sev3: 0, sev4: 0, sev5: 0}
    and .versions == {}
    and .violations == []
' "$testRoot/corrupt-local-output/output.json" >/dev/null
unset MOCK_LOCAL_STATUS

export MOCK_LOCAL_STATUS=no-output
run_case missing-local-output "" 0 0 "" cls "" "code-analyzer.yaml" 1
grep -q '^copado -p Writing to result -e Local Code Analyzer did not produce a valid report\.$' \
    "$testRoot/missing-local-output/function.log"
jq -e '
    .runDir == "."
    and .violationCounts == {total: 0, sev1: 0, sev2: 0, sev3: 0, sev4: 0, sev5: 0}
    and .versions == {}
    and .violations == []
' "$testRoot/missing-local-output/output.json" >/dev/null
unset MOCK_LOCAL_STATUS

# 13g. Structurally invalid ApexGuru output or merge failure preserves the valid local report and local exit status.
export MOCK_APEXGURU_STATUS=bad-violations
export MOCK_APEXGURU_EXIT_CODE=2
run_case apexguru-bad-violations "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q "did not complete remote analysis" "$testRoot/apexguru-bad-violations/function.log"
test "$(jq -r '.violations[0].rule' "$testRoot/apexguru-bad-violations/output.json")" = "LocalRule"
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_EXIT_CODE

export MOCK_APEXGURU_STATUS=merge-fail
export MOCK_APEXGURU_EXIT_CODE=2
run_case apexguru-merge-failure "test-access-token" 1 0 "" cls "" "code-analyzer.yaml" 0
grep -q "report could not be merged" "$testRoot/apexguru-merge-failure/function.log"
test "$(jq -r '.violations[0].rule' "$testRoot/apexguru-merge-failure/output.json")" = "LocalRule"
unset MOCK_APEXGURU_STATUS MOCK_APEXGURU_EXIT_CODE

# Live mode preservation is a report contract, not proof of org eligibility.
for mode in full static; do
    export MOCK_APEXGURU_ANALYSIS_MODE="$mode"
    run_case "mode-$mode" "test-access-token" 2 1
    test "$(jq -r '.insights.apexguru.analysisMode' output.json)" = "$mode"
done
unset MOCK_APEXGURU_ANALYSIS_MODE

# Explicit expected outcomes; the real CLI smoke independently tests this contract.
export branchesAndFileIdJson='{"originBranch":"promotion/LOCAL","destinationBranch":"int"}'
export targetBranch=int baseBranch= MOCK_AUTO_THRESHOLD=1
for row in '4 2 0' '4 4 4' '2 2 2' '2 1 0'; do
    read -r MOCK_LOCAL_SEVERITY severityThreshold expected <<< "$row"
    export MOCK_LOCAL_SEVERITY severityThreshold
    run_case "threshold-$MOCK_LOCAL_SEVERITY-$severityThreshold" "" 1 0 "" cls "" "code-analyzer.yaml" "$expected"
    grep -qF -- "--severity-threshold $severityThreshold" sf-calls.log
    grep -qF 'git:merge-base origin/promotion/LOCAL origin/int' sf-calls.log
    grep -q 'In promotion context' function.log
    grep -q '^copado -u output.json$' function.log
done
unset MOCK_LOCAL_SEVERITY MOCK_AUTO_THRESHOLD

echo "ApexGuru function tests passed."
