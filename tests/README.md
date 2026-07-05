# tests/

The testing landscape has three layers, each in its own place.

## Tooling tests (this directory)

`tests/*.sh` are focused shell/unit tests for the repo's own automation, not for infrastructure.
They are self-contained (no real AWS, no real providers) and run directly:

```sh
tests/implementer_status_test.sh    # implementer run status classification
tests/telemetry_test.sh             # the observability telemetry helper + runs.sh
```

Add a test here whenever you add or change tooling under `scripts/` (especially `scripts/lib/`).

## Module tests (`modules/<name>/tests/`)

Native `terraform test` in HCL, no Go toolchain:

```sh
terraform -chdir=modules/<name> test
```

These live next to the module they exercise (e.g. `modules/static-site/tests/static_site.tftest.hcl`).
Thin now, they grow as modules gain logic.

## Post-apply smoke tests

After each CI apply, the pipeline verifies the deployed resources actually work.
`scripts/smoke.sh <root>` is the generic, best-effort check (if a root exposes a `website_endpoint` output, it asserts HTTP 200).
Per-stack smoke tests are intended to grow under this directory; a failing smoke test fails the deployment.

See DESIGN.md "QA and testing" for how these fit the pipeline.
