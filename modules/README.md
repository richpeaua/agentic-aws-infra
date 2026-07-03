# modules/

Shared, reusable Terraform modules live here.

Create a module when the same set of resources is needed by more than one stack.
Keep single-use infrastructure inline in its stack under `stacks/<name>/`.

Prefer vetted community modules from the `terraform-aws-modules/*` registry namespace for complex or fiddly infrastructure (VPC, EKS, RDS, IAM policies).
Write raw resources for simple things.
Always pin versions.
