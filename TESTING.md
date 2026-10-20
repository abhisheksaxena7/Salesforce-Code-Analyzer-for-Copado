# Testing

This is the reusable testing runbook for contributors and agents. It defines
verification scope, commands, safety controls and evidence expectations for future
iterations. Keep release results and exceptions in
[release verification records](docs/releases/apexguru-verification.md).

## Three testing tiers

| Tier                       | Verification target                                                                                                                                                                          |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 — Local                  | Local mocks/contracts; optional real-engine Docker verification.                                                                                                                             |
| 2 — Unpackaged integration | Install the GA package in a Copado test org, deploy candidate function/template/LWC changes directly, and run the applicable integration scenario matrix before packaging.                   |
| 3 — Packaged verification  | In a separate org, exercise the existing GA gate before upgrading to the candidate package, then rerun Tier 2 scenarios through the installed package. Verify fresh installation separately. |

These tiers describe what is verified, not the increments used to implement the
automation. Record manually orchestrated runs as such; they can provide product
evidence without certifying an automated runner. Reuse designated isolated test
resources when appropriate; a new pipeline per run is not required. Verify
isolation before automated mutations.

## Tier 1: local verification

Run `npm run verify:local` for syntax, source/package parity, fixture/catalog
validation, verifier regression tests, pure resultTable transformation tests,
and the mocked function matrix. Requires Python 3, Bash, Node, jq, Git, and
Code Analyzer 5.16.0 installed in one of the function's supported plugin paths.
The mocks do not authenticate or contact an org. Discovery uses the installed
plugin; a missing plugin is a failed prerequisite, not full discovery coverage.

Optionally run `npm run verify:container` for the same static checks plus container mocks
and real-engine smoke. Docker must already be running. The image builds once;
`npm run verify:container -- --skip-build` reuses it, but installed plugin pins
are still verified. `npm run verify:local -- --mode all` runs both host and
container checks. No timing guarantee is made; compare cold and warm runs.
No real `run.env`, credentials, or authenticated host directories are mounted.
Container tests have networking disabled and mount this repository read-only.

Each invocation writes `.agentia/runs/local-*/candidate-manifest.json`,
`evidence.json`, and `summary.md`. A failed prerequisite returns nonzero.
Fast mode reports container tests as NOT_RUN. A fast PASS is not a container,
org, deployment, or release approval. CLI output is not persisted by the wrapper;
evidence records check status, exit code on failure, and timing. Run the named
local script directly for troubleshooting in the same credential-free environment.

The source manifest hashes code, fixture and test inputs and records the commit
and dirty-tree flag. It is explicitly NOT package-build provenance. Future
packaged verification must consume a manifest captured for the candidate build,
not infer provenance from the then-current working directory.

### Choosing Docker versus org verification

Docker is **optional for routine development and commits**. Keep
`npm run verify:local` as the default for code/test changes. Documentation-only
changes need formatting, links and diff checks, not runtime suites. Do not run
Docker automatically just because a commit or package candidate is being prepared.
The default command already skips Docker and records container tests as NOT_RUN.

Use container verification when changing Dockerfile/image inputs, CLI plugin or
Java versions, or diagnosing container-specific behavior. For those changes,
either verify locally or test the newly built exact image in Copado and record
its identity, versions and results. If image inputs changed, do not use
`--skip-build` against an older image. An org using the previous published image
cannot establish correctness of the changed Dockerfile.

Tier 2 org tests provide stronger evidence for real Copado orchestration,
credentials, ApexGuru and result uploads. Tier 3 adds package installation and
upgrade proof. They can be preferred over duplicate Docker runs when the image
is unchanged. Keep host mocks: live happy-path tests do not replace deliberate
missing-output, malformed-report, timeout, cancellation and recovery tests.
Skipping Docker does not waive applicable Tier 2 or Tier 3 checks, and a skipped
container check must never be reported as passed.

### Coverage boundaries

| Check                  | Proves                                                                                                                    | Does not prove                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| Function mocks         | Branch args, selectors, targets, mode preservation, threshold forwarding, failures, redaction, merge/upload orchestration | Actual engine behavior or Copado lifecycle            |
| Real-engine smoke      | Real local Git delta, CLI pins, Java availability, PMD/Regex/Flow/ESLint reports, real threshold outcomes                 | Remote ApexGuru, Salesforce compilation or deployment |
| Source/package parity  | Script, parameters, image, template/step identity, parent, viewer and custom metadata alignment                           | Extension generation or upgrade in an org             |
| Pure resultTable tests | Actual source's transformation, grouping, filtering, empty and unknown engine handling                                    | LWC rendering, LDS, browser interaction               |

Real-engine smoke creates two synthetic commits only in its disposable temporary
repository. It does not commit or push this project. Only `copado` and
`copado-git-get` are mocked; `git`, `sf sgd`, and `sf code-analyzer` remain real.
It separately checks severity-2 findings at thresholds 1/2 and severity-4 findings
at thresholds 2/4. The smoke configuration intentionally excludes remote and
expensive engines; it is not all-engine certification.

### Fixtures and scenarios

Repository ESLint commands/hooks target production `force-app` LWC/Aura files.
They deliberately exclude analyzer fixtures, whose violations are test inputs.
Prettier ignores `test-data/` to preserve reviewed fixture bytes. This does not
exclude fixtures from Code Analyzer: their own ESLint configuration and the
scenario catalog still control analyzer testing. Review deliberate fixture edits
and their expected outcomes together.

`test-data/assertions/scenarios.v1.json` is the versioned catalog for TC1–TC14
and Phase 3a–3c. It records fixture subsets, config, threshold, lifecycle and
expected behavior. It is a specification for future live runners, not a claim
that the entire live matrix is automated. The old-API variant
must be renamed to `PermissionsException.cls-meta.xml` when assembled.

Fixtures are outside `force-app`, the package source directory. They intentionally
contain analyzer violations and must never be included in the extension package
or used as production examples. Their XML structure is checked locally; record org compilation and
deployability as NOT_VERIFIED until exercised for the tested fixture snapshot. Do not equate valid XML or a clean analyzer run with a valid deployment.

Counts from earlier runs are not baselines for changed fixtures. Do not assert
fixed totals for real engines: record observed counts and assert representative
rule/severity presence, expected threshold behavior, and that reported counts
reconcile with the actual violations. Retain exact counts in deterministic mocks,
where they verify our own report merging and counting logic. Engine upgrades
require review of the rule/severity expectations. Full ApexGuru capability
alone does not guarantee a particular runtime rule such as DmlInALoop. Remote
exact counts are not generic assertions; TC4's threshold outcome requires a
validated remote finding profile. Missing required capability is NOT_VERIFIED.
An engine with no findings must not be inferred to have been skipped.

Fixture version 2 adds `CriticalConstructorDml`, independently selectable through
the `critical` fixture set. PMD's native `ApexCSRF` rule reports Critical (1) for
its constructor DML; no severity override is used. TC14 uses the full fixture set
to check all five severity levels and a Critical-threshold failure. Assert presence,
not exact totals. Never execute this intentionally unsafe constructor. Existing
clean, severity4 and old-api subsets exclude it, preserving their threshold cases.

## Acceptance criteria for live execution and packaged verification

Before live mutations are enabled:

1. Require dedicated disposable remote environments/branches. A clone does not
   isolate environment-branch changes; no shared branch reset or cleanup commits.
2. Prove atomic shared lock acquisition/renewal/ownership, or explicitly use a
   single shared execution host. Expiry must not overlap active jobs.
3. Recover a crash after remote creation but before saving its ID without creating
   duplicates. Correlate jobs by returned IDs; confirm child-job termination before
   retry/cleanup. Preserve all attempts and separate TIMEOUT, ERROR and
   PASSED_AFTER_RETRY from clean success.
4. Snapshot only selected configuration and restore conflict-aware. Restoration
   conflicts and missing capabilities cannot yield unconditional release approval.
5. Packaged verification consumes immutable build provenance and specified GA and
   beta versions. Exercise the baseline gate before upgrade, preserve its identity,
   generate records twice, then run that existing gate without unpacked overwrites.
6. Verify successful deployment as well as blocking; test fresh installation
   separately. Package promotion remains explicit maintainer action outside tests.

Record implementation milestones separately from this runbook. Require tests according to
changed behavior: documentation-only edits do not need a full live matrix. Retain
sanitized machine-readable evidence; never persist credentials, including in
ignored journals. Keep fixture hashes, versions, image identity, attempts, and
scope with each result. Existing live evidence is historical, not automatically
applicable to a changed candidate.

## Tier 2 and Tier 3 execution

Only Tier 1 execution is automated in this branch. Run Tier 2 and Tier 3 manually
using the scenario catalog and the deployment/package workflow in
[CONTRIBUTING.md](CONTRIBUTING.md). Integration runner implementation is deferred;
no simulation, org preflight or historical-job command is shipped here.

For Tier 2, install the baseline GA package in a designated test org, deploy the
candidate sources, and execute the applicable catalog scenarios. Record the
source commit and any uncommitted changes, fixture/configuration hashes, runtime
versions, job/result references, expected outcomes and observed outcomes. A gate
that fails at the expected severity threshold can be a passing test; distinguish
that from an infrastructure error or a test that never ran.

For Tier 3, record the baseline and candidate package versions and immutable
candidate build provenance. In a separate org, run the existing GA gate before
upgrading. Upgrade, verify existing gate identity and repeatable extension-record
generation, and rerun the applicable Tier 2 scenarios through the installed
package without unpackaged overwrites. Verify successful deployment and a
separate fresh installation before public release.

Keep retries and unresolved failures in the evidence. Missing capabilities and
unexecuted scenarios remain NOT_VERIFIED or NOT_RUN, never implicit passes.
Release approval and package promotion remain explicit maintainer decisions.
