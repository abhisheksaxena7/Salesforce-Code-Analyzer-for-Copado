#!/bin/bash
set -euo pipefail

########## Get Source and Destination Branch names and Checkout Repository #############
copado -p "Reading parameters..."
originBranch=$(jq -r '.originBranch' <<< $branchesAndFileIdJson)
BRANCH="$originBranch"
destinationBranch=$(jq -r '.destinationBranch' <<< $branchesAndFileIdJson)

echo "param originBranch = $originBranch"
echo "param destinationBranch = $destinationBranch"

copado -p "Cloning repo..."
copado-git-get $destinationBranch
copado-git-get $BRANCH

########## Read Severity from System Property on the Pipeline record, or default to 2 #############
if [ -z "${severityThreshold:-}" ] || [ -z "$(echo "$severityThreshold" | tr -d '[:space:]')" ]; then
    severityThreshold=2
elif ! [[ "$severityThreshold" =~ ^[1-5]$ ]]; then
    severityThreshold=2
fi

########### Create delta packages for new, modified or deleted metadata  ############
copado -p "Generating Diff between the Source and Destination branches..."
mkdir changed-sources
sf sgd source delta --to "HEAD" --from "origin/$destinationBranch" --output-dir changed-sources/ --generate-delta --source .
echo "Here's the files that have been changes in this US"
cat changed-sources/package/package.xml

################ Run Code Analyzer only on Changed Metadata  ###############
copado -p "Running Code Analyzer..."
exitCode=0
errorMessage=""
sf code-analyzer run --rule-selector all --workspace ./changed-sources/ --view detail --severity-threshold $severityThreshold --output-file ./output.json > stdout.log 2> stderr.log || exitCode=$?
errorMessage=$(grep "^Error ([0-9]*):" stderr.log 2>/dev/null | sed -E 's/^Error \([0-9]*\): //g' 2>/dev/null || echo "")

############ Attach Results to the Function results record  ####################
copado -p "Uploading results..."
if [ -f "output.json" ]; then
    copado -u output.json
    copado -p "Writing to result" -e "${errorMessage}"
fi

copado -p "Code Analyzer scan completed."
exit $exitCode
