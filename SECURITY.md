# Security policy

*Audience: reporting a security issue in this repository.*

This is a public, reference agentic-infrastructure workflow.
It provisions AWS infrastructure through a gated GitOps pipeline and exposes no hosted service to third parties.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability): the repository's **Security** tab, then **Report a vulnerability**.
Do not open a public issue for a security report.

## Scope and secrets

- All AWS identifiers (account ID, bucket names, role ARNs, emails) are kept out of the repository by design; see "Secrets and scrubbing" in [`AGENTS.md`](./AGENTS.md). If you find such a value committed, report it as above.
- CI uses short-lived GitHub OIDC credentials and local work uses AWS SSO; there are no long-lived cloud credentials in this repo.
