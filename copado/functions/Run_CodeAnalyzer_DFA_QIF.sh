#!/bin/bash
set -euo pipefail

########## Get Source and Destination Branch names and Checkout Repository #############
copado -p "Reading parameters..."
originBranch=$(jq -r '.originBranch' <<< $branchesAndFileIdJson)
BRANCH="$originBranch"
destinationBranch=$(jq -r '.destinationBranch' <<< $branchesAndFileIdJson)

echo "param branchesAndFileIdJson =  $branchesAndFileIdJson"
echo "param originBranch = $originBranch"
echo "param BRANCH = $BRANCH"

copado -p "cloning repo..."
copado-git-get $destinationBranch
copado-git-get $BRANCH

########### Create delta packages for new, modified or deleted metadata  ############
copado -p "Generating Diff between the Source and Destination branches..."
mkdir changed-sources
sfdx sgd:source:delta --to "HEAD" --from "origin/$destinationBranch" --output changed-sources/ --generate-delta --source .
echo "Here's the files that have been changes in this US"
cat changed-sources/package/package.xml 
echo

################ Run SFDX Scanner only on Changed Metadata  ###############
#TODO change html format with sarif, once the sarif viewer is generic enough
copado -p "running sfdx scanner:dfa..."
exitCode=0
sfdx scanner:run:dfa --format html --projectdir "./changed-sources/"  --target "./changed-sources/**/*.*" --severity-threshold $severityThreshold --outfile ./result-dfa.html || exitCode=$?

############ Attach Results to the Function results record  ####################
if [ -f "result-dfa.html" ]; then
    copado -u result-dfa.html
fi

echo "sfdx scanner scan completed. exit code: $exitCode"
exit $exitCode