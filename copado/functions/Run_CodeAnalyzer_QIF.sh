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

########### Create delta packages for new, modified or deleted metadata  ############
copado -p "Generating Diff between the Source and Destination branches..."
mkdir changed-sources
sf sgd source delta --to "HEAD" --from "origin/$destinationBranch" --output changed-sources/ --generate-delta --source .
echo "Here's the files that have been changes in this US"
cat changed-sources/package/package.xml

################ Run Code Analyzer only on Changed Metadata  ###############
copado -p "Running Code Analyzer..."
exitCode=0
sf code-analyzer run --rule-selector all --workspace ./changed-sources/ --view detail --severity-threshold $severityThreshold --output-file ./output.json || exitCode=$?

############ Attach Results to the Function results record  ####################
copado -p "Uploading results..."
if [ -f "output.json" ]; then
    copado -u output.json
    copado -p "Writing to result" -e "There was an error running Code Analyzer, please check logs for details."
fi

echo "Code Analyzer scan completed. exit code: $exitCode"
exit $exitCode
