#!/bin/bash
set -euo pipefail

########## Get Source and Destination Branch names and Checkout Repository #############
copado -p "Reading parameters..."
originBranch=$(jq -r '.originBranch' <<< $branchesAndFileIdJson)
echo "param originBranch = $originBranch"

########## Conditional logic for destinationBranch based on branch patterns and parameters ##########
if [[ "$originBranch" =~ ^promotion/.* ]] && [[ -n "${targetBranch:-}" ]] && [[ -z "${baseBranch:-}" ]]; then
    destinationBranch="$targetBranch"
    echo "In promotion context, using targetBranch as the destinationBranch."
elif [[ "$originBranch" =~ ^feature/.* ]] && [[ -n "${baseBranch:-}" ]] && [[ -z "${targetBranch:-}" ]]; then
    destinationBranch="$baseBranch"
    echo "In feature context, using baseBranch as the destinationBranch."
else
    destinationBranch=$(jq -r '.destinationBranch' <<< $branchesAndFileIdJson)
    echo "Context unclear, using destinationBranch from branchesAndFileIdJson"
fi
echo "param destinationBranch = $destinationBranch"

copado -p "Cloning repo..."
copado-git-get $destinationBranch
copado-git-get $originBranch

########## Read Severity from System Property on the Pipeline record, or default to 2 #############
severityThreshold="${severityThreshold:-}"
severityThreshold="${severityThreshold//[[:space:]]/}"
if ! [[ "$severityThreshold" =~ ^[1-5]$ ]]; then
    severityThreshold=2
fi

########### Create delta packages for new, modified or deleted metadata  ############
copado -p "Generating Diff between the Source and Destination branches..."
mkdir changed-sources
sf sgd source delta --to "origin/$originBranch" --from "$(git merge-base origin/$originBranch origin/$destinationBranch)" --output-dir changed-sources/ --generate-delta --source-dir .
echo "Here's the files that have been changes in this US"
cat changed-sources/package/package.xml

################ Helpers ###########################################################
is_resolved_param() {
    local value="${1:-}"
    value=$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$value" ]] && [[ ! "$value" =~ ^\{\$ ]]
}

write_empty_output_json() {
    local targetFile="${1:-./local-output.json}"
    jq -n '{
        runDir: ".",
        violationCounts: {total: 0, sev1: 0, sev2: 0, sev3: 0, sev4: 0, sev5: 0},
        versions: {},
        violations: []
    }' > "$targetFile"
}

# Discover enabled local Code Analyzer engines and whether ApexGuru is disabled
# from the installed plugin and any repo-root code-analyzer.yml / code-analyzer.yaml.
discover_code_analyzer_engines() {
    node --input-type=module <<'EOF' 2>/dev/null || true
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const candidates = process.env.CODE_ANALYZER_PLUGIN_DIR
    ? [process.env.CODE_ANALYZER_PLUGIN_DIR]
    : [
        process.env.XDG_DATA_HOME && path.join(process.env.XDG_DATA_HOME, "sf/node_modules/@salesforce/plugin-code-analyzer"),
        path.join(os.homedir(), ".local/share/sf/node_modules/@salesforce/plugin-code-analyzer"),
        path.join(os.homedir(), ".local/share/sfdx/node_modules/@salesforce/plugin-code-analyzer"),
        "/usr/local/lib/node_modules/@salesforce/plugin-code-analyzer",
        "/usr/local/lib/sf/node_modules/@salesforce/plugin-code-analyzer"
    ].filter(Boolean);

const pluginPkg = candidates.map(dir => path.join(dir, "package.json")).find(pkg => fs.existsSync(pkg));
if (!pluginPkg) process.exit(1);

const req = createRequire(pluginPkg);
const importFromPlugin = id => import(pathToFileURL(req.resolve(id)).href);
const [{ CodeAnalyzerConfigFactoryImpl }, { getValueUsingCaseInsensitiveKey }] = await Promise.all([
    importFromPlugin("./lib/lib/factories/CodeAnalyzerConfigFactory.js"),
    importFromPlugin("@salesforce/code-analyzer-engine-api")
]);

let config;
try {
    config = new CodeAnalyzerConfigFactoryImpl().create();
} catch {
    config = { getEngineOverridesFor: () => ({}) };
}

const isDisabled = name =>
    getValueUsingCaseInsensitiveKey(config.getEngineOverridesFor(name), "disable_engine") === true;

const { EnginePluginsFactoryImpl } = await importFromPlugin("./lib/lib/factories/EnginePluginsFactory.js");
const engines = new EnginePluginsFactoryImpl().create().flatMap(plugin => plugin.getAvailableEngineNames());
const localEngines = engines.filter(name => name.toLowerCase() !== "apexguru" && !isDisabled(name));

process.stdout.write(JSON.stringify({
    localEngines,
    apexGuruDisabled: isDisabled("apexguru")
}));
EOF
}

# Populate localRuleSelectorArgs and apexGuruDisabled from plugin discovery and
# code-analyzer.yml. Falls back to --rule-selector all --rule-selector uibundle
# if discovery fails. Customize engines via code-analyzer.yml, not a function param.
load_code_analyzer_settings() {
    local discoveryJson discovered engineName selector
    local selectors=()

    discoveryJson=$(discover_code_analyzer_engines)
    apexGuruDisabled="false"
    if [[ -n "$discoveryJson" ]] && [[ "$(jq -r '.apexGuruDisabled // false' <<<"$discoveryJson" 2>/dev/null)" == "true" ]]; then
        apexGuruDisabled="true"
    fi

    if [[ -n "$discoveryJson" ]]; then
        discovered=$(jq -r '.localEngines[]?' <<<"$discoveryJson" 2>/dev/null || true)
        while IFS= read -r engineName; do
            [[ -n "$engineName" ]] && selectors+=("$engineName")
        done <<<"$discovered"
    else
        selectors=("all" "uibundle")
    fi

    localRuleSelectorArgs=()
    if [[ "${#selectors[@]}" -gt 0 ]]; then
        for selector in "${selectors[@]}"; do
            localRuleSelectorArgs+=(--rule-selector "$selector")
        done
    fi
}

changed_sources_has_scannable_files() {
    find ./changed-sources \
        -path ./changed-sources/package -prune -o \
        -path ./changed-sources/destructiveChanges -prune -o \
        -type f -print -quit 2>/dev/null | grep -q .
}

build_apexguru_target_args() {
    apexGuruTargetArgs=()
    if find ./changed-sources -type f -name '*.cls' -print -quit 2>/dev/null | grep -q .; then
        apexGuruTargetArgs+=(--target './changed-sources/**/*.cls')
    fi
    if find ./changed-sources -type f -name '*.trigger' -print -quit 2>/dev/null | grep -q .; then
        apexGuruTargetArgs+=(--target './changed-sources/**/*.trigger')
    fi
}

redact_sensitive_text() {
    local text="${1:-}"
    local secret="${2:-}"
    if [[ -n "${secret//[[:space:]]/}" ]]; then
        text=${text//$secret/[redacted]}
    fi
    text=$(printf '%s' "$text" | sed -E 's/00D[A-Za-z0-9]{12,}![A-Za-z0-9._+-]+/[redacted]/g')
    text=$(printf '%s' "$text" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
    printf '%s' "${text:0:240}"
}

redact_log_reason() {
    local logFile="$1"
    local secret="${2:-}"
    local outputJsonFile="${3:-}"
    local reason=""

    if [[ -n "$outputJsonFile" && -f "$outputJsonFile" ]]; then
        reason=$(jq -r '.insights.apexguru.error.message // empty' "$outputJsonFile" 2>/dev/null || true)
        if [[ -z "$reason" ]]; then
            reason=$(jq -r '[
                .violations[]?
                | select(.rule == "UnexpectedEngineError" or .rule == "UninstantiableEngineError")
                | .message
            ] | first // empty' "$outputJsonFile" 2>/dev/null || true)
        fi
    fi
    if [[ -z "$reason" && -f "$logFile" ]]; then
        reason=$(grep -E -i 'error|invalid|unauthorized|auth|failed' "$logFile" | head -n 1 || true)
        if [[ -z "$reason" ]]; then
            reason=$(tail -n 1 "$logFile" || true)
        fi
    fi
    redact_sensitive_text "$reason" "$secret"
}

endpoint_origin() {
    local endpoint="$1"
    endpoint=$(printf '%s' "$endpoint" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [[ "$endpoint" =~ ^(https?://[^/?#]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$endpoint"
    fi
}

analyzer_output_is_valid() {
    local targetFile="$1"
    [[ -s "$targetFile" ]] && jq -e '
        type == "object"
        and (.runDir | type == "string")
        and (.violationCounts | type == "object")
        and (.violationCounts.total | type == "number")
        and (.violationCounts.sev1 | type == "number")
        and (.violationCounts.sev2 | type == "number")
        and (.violationCounts.sev3 | type == "number")
        and (.violationCounts.sev4 | type == "number")
        and (.violationCounts.sev5 | type == "number")
        and ((.versions // {}) | type == "object")
        and ((.insights // {}) | type == "object")
        and (.violations | type == "array")
    ' "$targetFile" >/dev/null 2>&1
}

apexguru_output_is_usable() {
    analyzer_output_is_valid ./apexguru-output.json && jq -e '
        (.insights.apexguru.status // "completed") == "completed"
        and (([.violations[] | select((type == "object") and (.rule == "UnexpectedEngineError" or .rule == "UninstantiableEngineError"))] | length) == 0)
    ' ./apexguru-output.json >/dev/null 2>&1
}

merge_analyzer_outputs() {
    if ! analyzer_output_is_valid ./local-output.json; then
        write_empty_output_json ./local-output.json
    fi

    cp ./local-output.json ./output.json

    if [[ "$apexGuruUsable" == "true" ]]; then
        if jq -s '
            .[0] as $local
            | .[1] as $guru
            | ((($local.violations // []) | map(select(.engine != "apexguru")))
                + (($guru.violations // []) | map(select(.engine == "apexguru")))) as $violations
            | $local
            | .violations = $violations
            | .versions = (($local.versions // {}) + ($guru.versions // {}))
            | .insights = (($local.insights // {}) + ($guru.insights // {}))
            | .violationCounts = {
                total: ($violations | length),
                sev1: ([$violations[] | select(.severity == 1)] | length),
                sev2: ([$violations[] | select(.severity == 2)] | length),
                sev3: ([$violations[] | select(.severity == 3)] | length),
                sev4: ([$violations[] | select(.severity == 4)] | length),
                sev5: ([$violations[] | select(.severity == 5)] | length)
            }
        ' ./local-output.json ./apexguru-output.json > ./merged-output.json 2>/dev/null \
            && analyzer_output_is_valid ./merged-output.json; then
            mv ./merged-output.json ./output.json
            return 0
        fi
        rm -f ./merged-output.json
        return 1
    fi
    return 0
}

################ Run Code Analyzer only on Changed Metadata  ###############
# ApexGuru is a remote engine in Code Analyzer 5.16.0. Run it separately so
# missing org access never prevents the existing local engines from completing.
# Local engines are discovered dynamically from the installed plugin minus
# apexguru, respecting code-analyzer.yml disable_engine settings.
copado -p "Running Code Analyzer local engines..."
exitCode=0
localExitCode=0
localScanAttempted="false"
localReportError=""
apexGuruExitCode=0
apexGuruWarning=""
apexGuruUsable="false"
errorMessage=""
localRuleSelectorArgs=()
apexGuruTargetArgs=()
apexGuruDisabled="false"

load_code_analyzer_settings
echo "Local rule selectors: ${localRuleSelectorArgs[*]:-(none)}"

if [[ "${#localRuleSelectorArgs[@]}" -eq 0 ]] || ! changed_sources_has_scannable_files; then
    write_empty_output_json ./local-output.json
else
    localScanAttempted="true"
    sf code-analyzer run \
        "${localRuleSelectorArgs[@]}" \
        --workspace ./changed-sources/ \
        --include-fixes \
        --include-suggestions \
        --view detail \
        --severity-threshold "$severityThreshold" \
        --output-file ./local-output.json \
        > local-stdout.log 2> local-stderr.log || localExitCode=$?
fi

if [[ "$localScanAttempted" == "true" ]] && ! analyzer_output_is_valid ./local-output.json; then
    localReportError="Local Code Analyzer did not produce a valid report."
    write_empty_output_json ./local-output.json
    if [[ "$localExitCode" -eq 0 ]]; then
        localExitCode=1
    fi
fi

exitCode=$localExitCode

# Capture and immediately clear the sensitive session ID from the environment.
sessionId="${apexGuruSessionId:-}"
unset apexGuruSessionId
build_apexguru_target_args

if [[ "$apexGuruDisabled" == "true" ]]; then
    apexGuruWarning="ApexGuru was skipped because it is disabled in the Code Analyzer configuration."
elif [[ "${#apexGuruTargetArgs[@]}" -eq 0 ]]; then
    apexGuruWarning="ApexGuru was skipped because the change contains no Apex classes or triggers."
elif ! is_resolved_param "$sessionId" || ! is_resolved_param "${apexGuruEndpoint:-}"; then
    apexGuruWarning="ApexGuru was skipped because no source-environment credential was available."
else
    apexGuruOrigin=$(endpoint_origin "$apexGuruEndpoint")
    copado -p "Configuring the source environment for ApexGuru..."
    if sf config set "org-instance-url=$apexGuruOrigin" \
        > apexguru-auth-stdout.log 2> apexguru-auth-stderr.log; then
        echo "ApexGuru target args: ${apexGuruTargetArgs[*]}"
        copado -p "Running ApexGuru on changed Apex classes and triggers..."
        sf code-analyzer run \
            --rule-selector apexguru \
            --workspace ./changed-sources/ \
            "${apexGuruTargetArgs[@]}" \
            --target-org "$sessionId" \
            --include-fixes \
            --include-suggestions \
            --view detail \
            --severity-threshold "$severityThreshold" \
            --output-file ./apexguru-output.json \
            > apexguru-stdout.log 2> apexguru-stderr.log || apexGuruExitCode=$?
        apexGuruReason=$(redact_log_reason ./apexguru-stderr.log "$sessionId" ./apexguru-output.json)
        sessionId=""

        if apexguru_output_is_usable; then
            apexGuruUsable="true"
        else
            apexGuruWarning="ApexGuru was skipped because the source environment did not complete remote analysis."
            if [[ -n "$apexGuruReason" ]]; then
                apexGuruWarning="$apexGuruWarning $apexGuruReason"
            fi
            apexGuruExitCode=0
        fi
    else
        apexGuruReason=$(redact_log_reason ./apexguru-auth-stderr.log "$sessionId")
        sessionId=""
        apexGuruWarning="ApexGuru was skipped because the source environment could not be authenticated."
        if [[ -n "$apexGuruReason" ]]; then
            apexGuruWarning="$apexGuruWarning $apexGuruReason"
        fi
    fi
fi
sessionId=""

if ! merge_analyzer_outputs; then
    apexGuruUsable="false"
    apexGuruExitCode=0
    if [[ -z "$apexGuruWarning" ]]; then
        apexGuruWarning="ApexGuru was skipped because its report could not be merged."
    fi
fi

if [[ "$apexGuruUsable" == "true" ]]; then
    if [[ "$apexGuruExitCode" -ne 0 ]] \
        && [[ "$exitCode" -eq 0 || "$apexGuruExitCode" -lt "$exitCode" ]]; then
        exitCode=$apexGuruExitCode
    fi
fi

if [[ -n "$apexGuruWarning" ]]; then
    apexGuruWarning=$(redact_sensitive_text "$apexGuruWarning")
    copado -p "$apexGuruWarning"
fi

cat local-stdout.log 2>/dev/null > stdout.log || true
cat local-stderr.log 2>/dev/null > stderr.log || true
if [[ "$apexGuruUsable" == "true" ]]; then
    cat apexguru-stdout.log 2>/dev/null >> stdout.log || true
    cat apexguru-stderr.log 2>/dev/null >> stderr.log || true
fi
errorMessage=$(grep -E "^Error \\([0-9]+\\):" stderr.log 2>/dev/null | sed -E 's/^Error \([0-9]+\): //g' || true)
if [[ -z "$errorMessage" && -n "$localReportError" ]]; then
    errorMessage="$localReportError"
fi
errorMessage=$(redact_sensitive_text "$errorMessage")

############ Attach Results to the Function results record  ####################
copado -p "Uploading results..."
if [ -f "output.json" ]; then
    copado -u output.json
    copado -p "Writing to result" -e "${errorMessage}"
fi

copado -p "Code Analyzer scan completed."
exit $exitCode