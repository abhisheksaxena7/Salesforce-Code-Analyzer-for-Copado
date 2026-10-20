# Analyzer fixtures

Deliberately problematic sample metadata for local and future live tests. These
files are not part of the extension package. Never deploy to production.

Apex/Visualforce/message-channel examples were brought into this repository from
the project's existing US-0000027 playground fixtures; no external branch is
needed to run them now. The clean class and Flow were adjusted, and a minimal
LWC fixture was added. The LWC has no data access and intentionally uses console
logging for an ESLint finding; its paragraph needs no custom styling or controls.

See [testing guidance](../TESTING.md) and
[scenario catalog](assertions/scenarios.v1.json). XML checks are not deployment
validation. Full/static remote counts must be established for a controlled org
profile; historical totals must not be copied as expectations for these fixtures.

Fixture version 2 adds `CriticalConstructorDml.cls`: constructor DML deliberately
triggers PMD `ApexCSRF` at native Critical (1), without configuration overrides.
Use the `critical` subset for an independent reproduction or the `full` subset
for TC14's all-five-severities check. Never instantiate this class or deploy it to
production. Assert rule/severity presence and report-count consistency rather than
fixed violation totals, which can change with engine versions.
