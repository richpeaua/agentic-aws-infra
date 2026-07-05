<!--
Keep this structure. It makes every change reviewable and auditable the same way.
Delete the HTML comments before submitting.

For a docs-only or non-infrastructure change (no Terraform authored), use the
"Docs / non-infra changes" variant at the bottom instead of the Terraform
sections, and delete the Terraform sections (Plan, Cost, Review panel findings,
and the infrastructure Definition of Done).
-->

## Summary

<!-- What this change does and why, in a sentence or two. -->

## Scope

- Stack(s):
- Environments affected: dev / prod
- Change type: new stack / modify / destroy / foundation / ci / docs

## Plan

<!-- Paste the key lines of `terraform plan` (adds/changes/destroys), or a summary.
     A destroy or replace must be called out explicitly here. -->

```
Plan: X to add, Y to change, Z to destroy.
```

## Cost

<!-- Infracost monthly delta from `scripts/plan.sh`. -->

Monthly cost delta:

## Review panel findings

<!-- Summary of the security / compliance / cost / correctness panel, and how each finding was resolved. -->

- Security:
- Compliance:
- Cost:
- Correctness:

## Definition of Done

- [ ] Stack is a module + `dev`/`prod` roots (used the scaffolder or matched its shape).
- [ ] `scripts/check.sh <root>` passes for the affected roots.
- [ ] `scripts/plan.sh <root>` shows only intended changes; a re-plan is a no-op.
- [ ] Infracost delta captured above.
- [ ] Review panel run; findings resolved or justified.
- [ ] `scripts/scan-secrets.sh` clean; no account IDs, buckets, ARNs, or emails committed.
- [ ] `default_tags` present; environment included in resource names.
- [ ] Provider and module versions pinned; lock file has linux + darwin hashes.
- [ ] No local apply of an application stack (apply happens in CI).

<!--
====================================================================
Docs / non-infra changes variant
Use this INSTEAD of Plan / Cost / Review panel findings / the Definition of
Done above when no Terraform is authored (docs, scripts, CI, tooling). Delete
the Terraform-only sections and keep the checklist below.
====================================================================
-->

## Definition of Done (docs / non-infra)

- [ ] `scripts/scan-secrets.sh` clean; no account IDs, buckets, ARNs, or emails committed.
- [ ] Relative links and section anchors in changed docs resolve.
- [ ] No net information loss: moved content has a single, findable home.
- [ ] No infrastructure change (no `terraform apply`/`destroy`); Terraform sections above removed as N/A.
