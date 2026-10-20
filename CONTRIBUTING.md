# Contributing

This project packages Salesforce Code Analyzer as a Copado quality-gate
extension. Contributions normally touch three representations of the same
behavior: the function/template sources, Copado records, and the packaged
static resource.

## Prerequisites

Install:

- Git.
- Python 3 for local verification (standard library only; no pip dependencies).
- Docker Desktop or Docker Engine with Buildx (optional; for container verification).
- Salesforce CLI (`sf`).
- Node.js 20 or newer when installing Salesforce CLI plugins through npm.
- `jq` and Bash for local diagnostics.

Install the CopadoDev Salesforce CLI plugin when function or template records
must be deployed:

```bash
sf plugins install @copado/copadodev-cli
sf copado beta function deploy --help
```

Agentia CLI is optional but recommended for inspecting Copado runtime state:

```bash
npm install --global @copado/agentia-cli
agentia auth get --json
```

Do not silently upgrade project dependencies. Check published versions first,
pin released analyzer plugins exactly in `copado/images/Dockerfile`, and review
release notes before changing a pin.

```bash
npm view @salesforce/plugin-code-analyzer version time --json
```

## Required Salesforce environments

Use generic aliases such as `control-org` and `analysis-org`; never commit
personal org names or IDs.

1. **Copado control org**: a non-production org with the required Copado
   packages, this extension package, Copado Functions access, and an
   authenticated repository/pipeline. Function and job-template records are
   deployed here.
2. **ApexGuru analysis org**: an ApexGuru-eligible Production or Full Copy org
   with ApexGuru activated and an integration user assigned the required
   ApexGuru permission set. Developer Edition and unsupported sandbox types
   cannot provide ApexGuru analysis.
3. **Copado environment credential**: an authenticated Copado Environment
   record for the analysis org. A single credential is sufficient because the
   source being analyzed is the Git delta, not metadata retrieved from the org.

The control and analysis roles can use the same org only when that org is
eligible and doing so complies with the organization's security policy.

Authenticate local aliases when direct CLI testing is needed:

```bash
sf org login web --alias control-org
sf org login web --alias analysis-org
sf org list
```

Never paste or log an access token. For automation, pass it through
`SF_ACCESS_TOKEN` and remove it from the environment after login.

## Initial setup

1. Clone the repository and create a feature branch.
2. If choosing container verification, confirm Docker is running with `docker info`.
3. Confirm org authentication with `sf org display --target-org <alias>`.
4. Install the current released extension package in the control org when a
   baseline is required:

   ```bash
   sf package install --package <package-version-id> \
     --target-org control-org --wait 20 --publish-wait 10 --no-prompt
   ```

5. Copy `copado/local/run.env.sample` to `copado/local/run.env` only for manual
   local runs. Keep real credentials outside Git.

## Change workflow

Keep these artifacts synchronized:

- `copado/functions/Run_CodeAnalyzer_QIF.sh`
- `copado/functions/Run_CodeAnalyzer_QIF.metadata.json`
- `copado/templates/Run SFDX Codeanalyzer QIF_1.template.json`
- `copado/templates/Run SFDX Codeanalyzer QIF_1.metadata.json`
- `force-app/main/default/staticresources/CopadoSFDXAnalyzer.json`

The static resource contains escaped JSON and an embedded copy of the function
script. Validate it after every synchronization:

```bash
jq empty \
  "copado/templates/Run SFDX Codeanalyzer QIF_1.template.json" \
  "copado/templates/Run SFDX Codeanalyzer QIF_1.metadata.json" \
  force-app/main/default/staticresources/CopadoSFDXAnalyzer.json
```

Keep local engines and remote ApexGuru execution independent. If the analysis
org is absent or unsupported, upload the local-engine result and report a clear
warning. Merge successful ApexGuru violations, versions, insights, and severity
counts into the existing `output.json` contract.

## Local verification

For routine code/test changes, run the host checks without Docker:

```bash
npm run verify:local
```

Docker is optional for routine development and commits. To check the container
runtime, run `npm run verify:container`; use `-- --skip-build` only when the image
inputs are unchanged. Do not run the container suite automatically for every edit.

When image inputs, CLI/plugin/Java versions, or container-specific behavior change,
verify the intended image either locally or in Copado after infrastructure builds
it. Record the image identity, exact Code Analyzer version, Java version and test
outcomes. Running an org against an older image does not test a new Dockerfile.
Retain the host mocks for failure/recovery and redaction cases; a successful live
scan alone does not cover those cases. Report skipped Docker checks as NOT_RUN.

For a live remote-engine check, create a temporary Apex class outside the
repository, authenticate `analysis-org`, and run `sf code-analyzer run` inside
the built image with `--rule-selector apexguru`, `--target-org`, and a JSON
output file. Confirm `insights.apexguru.status` is `completed`.

## Deploy to a control org

Deploy records with CopadoDev CLI:

```bash
sf copado beta function deploy \
  --name Run_CodeAnalyzer_QIF --targetusername control-org --json

sf copado beta template deploy \
  --name "Run SFDX Codeanalyzer QIF_1" \
  --targetusername control-org --json

sf project deploy start \
  --metadata StaticResource:CopadoSFDXAnalyzer \
  --target-org control-org --wait 20 --json
```

Verify the deployed Function parameters and Job Step configuration with
read-only SOQL before triggering a quality gate.

## Prepack the extension

`prepack` reads the deployed Copado records from the control org, overlays the
local function/template sources, and regenerates
`force-app/main/default/staticresources/CopadoSFDXAnalyzer.json`.

Before running it:

- Keep `copado/extension_manifest.json` current.
- Ensure every template step has a stable `apiname`.
- Deploy the latest function and template to the control org.
- Add `sfdx-scanner` to the control org's restricted Extension Tool picklist.
- Ensure an Extension Configuration record exists for that tool. Generating the
  extension records from a previously installed package can create it.

Then run:

```bash
sf copado beta extension prepack \
  --targetusername control-org --validate --json
```

Review the generated resource rather than treating it as an opaque artifact.
Confirm that it contains the expected Extension Configuration, template, step,
function parameters, image name, and current function script. The job step must
keep `copado__Result_Viewer_Component__c` set to `copado_labs:resultTable`;
without it Copado stores `output.json` but does not render the result. The
template step declares that value as `resultViewerComponent`, and prepack
copies the org step's custom fields, including this one. Also confirm that
custom metadata such as `copado__TestTool.sfdx_scanner` references the generated
template API name.

## Request a new image when runtime dependencies change

There is no CLI command that publishes a Copado Function image. If
`copado/images/Dockerfile` or another image input changes:

1. Choose the next immutable tag, such as `:v6` after `:v5`. Never reuse or
   overwrite a tag that an existing package version references.
2. Set that tag in `imagename` in the function `.metadata.json`.
3. Redeploy the function and rerun `prepack` so
   `copado__Image_Name__c` in the static resource uses the same tag.
4. Ask the Copado infrastructure team to build and publish that exact image.
   The new package must not be installed for runtime testing until the image
   exists.

Verify image changes with local container tests or with the newly built exact
image in Copado. A local image is not automatically the image Copado Functions
execute. If the Dockerfile did not change, keep the existing image tag.

## Create a beta package

After tests and `prepack` succeed, increment `versionName` and `versionNumber`
in `sfdx-project.json`. The new version must be greater than the latest package
version and should remain unreleased while it is being tested.

```bash
sf package version list \
  --packages copado-sfdx-scanner \
  --target-dev-hub dev-hub --json

sf package version create \
  --package copado-sfdx-scanner \
  --target-dev-hub dev-hub \
  --branch <feature-branch> \
  --installation-key-bypass \
  --wait 30 --json
```

Record the resulting subscriber package version ID (`04t...`) and install it in
a non-production packaging test org:

```bash
sf package install \
  --package <subscriber-package-version-id> \
  --target-org package-test-org \
  --wait 20 --publish-wait 10 --no-prompt --json
```

Generate the extension records and run a real quality gate from the installed
beta before requesting promotion. Do not use `--skip-validation` for a beta
that may later be promoted, and do not promote or release a version without
explicit maintainer approval.

## Inspect Copado with Agentia

Agentia uses the Copado API and is useful when the Salesforce object model is
not obvious:

```bash
agentia cicd pipeline get <pipeline-id> --json
agentia cicd environment get <environment-id> --json
agentia cicd credential list --environmentid <environment-id> --json
agentia cicd environment auth status <environment-id> \
  --credentialid <credential-id> --json
agentia cicd job list --type "<template-name>" --json
agentia cicd job get <job-id> --json
```

Use the job log and result-file commands to diagnose a real quality-gate run.
Agentia validates Copado credentials but intentionally does not reveal their
access tokens. Test those credentials by running the deployed quality gate.

## Before requesting review

- Run host tests for code/test changes, JSON validation, `git diff --check`, and
  applicable IDE lint checks. Container tests are optional unless needed to verify
  image/runtime changes; a verified exact-image org run can cover that runtime.
- For documentation-only edits, run relevant formatting/link/diff checks.
- Complete a non-production quality-gate run when runtime wiring changed.
- Confirm no secrets, org IDs, personal aliases, generated reports, or unrelated
  editor settings are included.
- Report skipped checks and their reason.
- Do not commit or push another contributor's unrelated work.

## Repeatable verification entrypoints

See [TESTING.md](TESTING.md) for fixtures, the versioned scenario catalog,
evidence, prerequisites, and mock-versus-live boundaries.

```bash
npm run verify:local
# Optional container verification:
npm run verify:container
```

The container command builds once and runs without host credentials or networking.
Use `-- --skip-build` to reuse a built image; plugin pins are still checked.

Only local verification is automated here. Run unpackaged-org and packaged
verification manually using [TESTING.md](TESTING.md) and the scenario catalog.
Integration runner automation is deferred. Keep candidate-specific decisions and
limitations in [release records](docs/releases/apexguru-verification.md).
