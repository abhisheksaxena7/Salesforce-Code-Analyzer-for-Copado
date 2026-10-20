# ApexGuru packaged-upgrade verification

On 2026-10-19, the agreed Tier 3 upgrade scope passed: a successful GA baseline,
upgrade preservation checks, and TC1–TC13 through the installed candidate.
**This is verification evidence, not public-release approval.**

See [TESTING.md](../../TESTING.md) for the testing policy and the
[versioned scenario catalog](../../test-data/assertions/scenarios.v1.json) for
individual test definitions.

## Tested build

| Item             | Version / provenance                                                                     |
| ---------------- | ---------------------------------------------------------------------------------------- |
| Baseline GA      | 3.5.0.1 — `04tP7000002KS73IAG`                                                           |
| Candidate        | 4.0.0.1 — `04tP7000003gvkvIAA`                                                           |
| Candidate commit | `676c6cd705d75d84dc25b2de36c9a89c9f245d1b` — maintainer-confirmed                        |
| Fixture commit   | `0b8501e501f4c616c6822d768d1aa9c1faf24f18`                                               |
| Function image   | Candidate's `v6` image, exercised in Copado; immutable digest not independently verified |

Testing was manually orchestrated in a separate package-test org. No unpackaged
Function, template, LWC or static-resource changes were deployed over the
candidate. Fixture hashes and execution evidence are retained privately.

## Results

| Coverage                  | Result                                                                                                           |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| GA baseline and upgrade   | Existing gate passed before upgrade; its identity and configuration survived                                     |
| Extension generation      | Repeated generation produced no active duplicates; parameters and result-viewer wiring verified                  |
| TC1–TC8: after commit     | Expected outcomes confirmed for full/static ApexGuru, disabled engines, ApexGuru-only, non-Apex and clean inputs |
| TC9–TC11: after promotion | Expected failure/pass/failure reporting confirmed at the configured thresholds                                   |
| TC12: before deployment   | Failing gate prevented the Deploy step from running                                                              |
| TC13: before deployment   | Passing gate allowed an actual successful Salesforce deployment (`checkOnly=false`)                              |

After-promotion gates are reporting-only and do not block deployment.
Before-deployment gates enforce deployment blocking. An expected threshold
failure is a passing test assertion, not a failed scan execution.

Reports passed schema and count reconciliation without engine-error findings.
ApexGuru full/static modes were confirmed by `insights.apexguru.analysisMode`,
not inferred from finding counts. Counts are specific to the tested fixtures.

## Observations and limitations

- Extension generation recreates JobStep records; it does not preserve every
  record ID. A remaining script-difference indicator was traced to a final
  newline difference in the stored script.
- TC9's concurrent deployment failed on a deployment-input packaging issue,
  separate from its correct reporting-gate outcome. TC13 independently proved
  actual deployment success with the class fixture. The Flow fixture passed
  validation only; actual Flow deployment was not verified.
- Failed attempts and unrelated acceptance-policy failures remain in private
  evidence. Historical results are not substituted for candidate execution.
- Fresh installation was **NOT_RUN**, excluded from this upgrade exercise. It
  remains required by the current testing policy before public release.
- Phase 3a/3b fault injection and the full Phase 3c interactive viewer matrix were
  **NOT_RUN** as packaged tests. Viewer wiring checks do not establish that UI
  coverage. This run does not certify the deferred integration runner.

Temporary branch mappings and threshold overrides were removed, and temporary
gates were inactivated. Test records, inactive gates and deployment fixtures were
retained for auditability. Detailed execution history, hashes and job references
are maintained in private evidence rather than this public summary.

No package promotion or release was performed. Remaining verification scope must
be addressed or explicitly dispositioned before release sign-off.
