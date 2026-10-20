# Agent Guide

Read `CONTRIBUTING.md` before changing this repository. It defines the required
software, Salesforce org roles, CLI setup, deployment workflow, and verification
steps.

## Repository architecture

- `copado/images/Dockerfile`: Copado Function image and exact CLI plugin pins.
- `copado/functions/`: function source plus matching `.metadata.json`.
- `copado/templates/`: job template source. Keep `.template.json` and
  `.metadata.json` equivalent.
- `force-app/main/default/staticresources/CopadoSFDXAnalyzer.json`: packaged
  extension records. Keep its parameters and embedded script synchronized with
  the function and template sources.
- `copado/local/`: Docker runner and function tests.

## Required behavior

- Work on a feature branch and preserve unrelated local changes.
- Pin released CLI plugins to exact versions; never use `latest` for a plugin.
- When the Dockerfile changes, assign the next image tag in function metadata.
  Do not overwrite a released tag and do not publish the image; Copado
  infrastructure builds the tag named by `imagename`.
- Never print, persist, or commit session IDs, access tokens, API keys, or org
  authentication files.
- Use one authenticated, ApexGuru-enabled analysis org. Source code comes from
  the Git delta; multiple org credentials are unnecessary.
- ApexGuru unavailability must not prevent local Code Analyzer engines from
  producing their report.
- Preserve the `output.json` schema consumed by `resultTable`.
- Do not commit or push until local and target-org verification succeeds and the
  contributor approves it.

## Three-tier testing and minimum verification

Follow [TESTING.md](TESTING.md), the canonical testing policy:

1. **Tier 1 — Local:** run `npm run verify:local` for code/test changes. Docker
   verification (`npm run verify:container`) is optional for routine development.
2. **Tier 2 — Unpackaged integration:** install GA in a test Copado org, deploy
   candidate source changes directly, and exercise the relevant integration
   scenarios; run the full applicable matrix before packaging.
3. **Tier 3 — Packaged verification:** in a separate org, exercise the GA baseline
   gate before upgrading to the candidate package, then rerun the Tier 2 scenarios.
   Verify fresh installation separately before public release.

Keep release-specific results and exceptions in `docs/releases/`. Keep TESTING.md
reusable across releases; track deferred automation work separately.
Do not equate historical evidence with a new run or package proof.

Do not run Docker automatically for every edit or commit. Use it when changing
image inputs, CLI/plugin/Java versions, or investigating container-specific
behavior. For those changes, verify the intended image locally or exercise the
newly built exact image in Copado, recording image identity, versions and test
outcomes. An org using an older image does not verify a new Dockerfile.
Record skipped Docker checks as NOT_RUN, not PASSED. Documentation-only changes
need relevant formatting/link/diff checks, not runtime suites. For code changes,
validate JSON, shell syntax, `git diff --check`, and applicable IDE diagnostics.

Use Salesforce CLI for org/package/metadata operations, CopadoDev CLI for
function and template records, and Agentia CLI for inspecting Copado pipelines,
environments, credentials, jobs, logs, and result files. Agentia intentionally
does not expose environment access tokens.

# Agentia CLI for AI Agents

<!-- agentia:managed:start -->

Use Agentia to manage Copado work items. Prefer registered Agentia MCP tools; otherwise use the CLI with `--json`.

Authentication must be configured before operational commands. Never print credentials, tokens, or unmasked environment variables.

## Copado workflow

`list → get → set → (implement & git commit) → test → publish → submit [--done|--deploy]`

Read records before changing them and use IDs returned by Copado. Do not skip `work set` before coding; use one story per feature branch. Keep the working tree clean for lifecycle commands, and confirm promotion/deployment intent before `done`.

## Agent Skills

Load exactly one copy of each applicable Agentia skill. Prefer the client-specific root when available (`.cursor/skills` in Cursor or `.claude/skills` in Claude); otherwise use `.agents/skills`.

- `agentia-cicd/SKILL.md`: Copado stories, commits, publish, submit, done, promotions, jobs, Functions, Job Templates, environments, pipelines, Slack notification configure, and data.
- `agentia-testing/SKILL.md`: Copado Robotic Testing operations.
- `agentia-ai/SKILL.md`: Copado AI operations.

Project rules in this file take precedence over managed skill guidance. Refresh managed skills with `agentia setup skills update`; do not hand-edit managed files.

<!-- agentia:managed:end -->

## Local test boundaries

Fixtures under `test-data/` intentionally contain violations and must remain
outside packaged source. Host mocks test failure/recovery cases that a successful
org scan does not cover; retain them even when Docker is skipped. Never treat a
local source manifest as package-build provenance.
