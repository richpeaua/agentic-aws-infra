# Agentic AWS Infrastructure Workflow

A laptop-driven workflow where a Claude Code agent authors Terraform, plans it, shows you the diff and cost, and applies it only after you approve.

See `DESIGN.md` for the full design and rationale.
The agent's operating procedure lives in `.claude/skills/provision-aws/SKILL.md`.

## How it works

1. You describe infrastructure in natural language.
2. The agent writes a Terraform stack under `stacks/<name>/`.
3. The agent runs `plan` and Infracost and shows you the changes and the monthly cost delta.
4. Nothing is applied or destroyed until you explicitly approve.
   The permission rules in `.claude/settings.json` enforce this: `apply` and `destroy` always prompt.

## One-time prerequisites (done by hand)

The agent cannot do these for you.

1. Create or designate a dedicated AWS account used only for this workflow.
2. In IAM Identity Center, create a permission set with `AdministratorAccess` and assign it to the account.
3. Install the tools:
   ```
   brew install terraform awscli infracost
   ```
   Terraform must be 1.10 or later (native S3 state locking).
4. Configure the SSO profile and log in:
   ```
   aws configure sso
   aws sso login
   export AWS_PROFILE=<your-profile-name>
   ```
5. Set up Infracost:
   ```
   infracost auth login
   ```
6. Verify:
   ```
   aws sts get-caller-identity
   terraform version
   infracost --version
   ```

## First run

### Step 0: bootstrap the state bucket and budget

```
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # then edit it
terraform init
terraform plan
```

Have the agent review the plan, then approve the apply.
After the bucket exists:

1. Uncomment the backend block in `bootstrap/backend.tf` and set `bucket` to the `state_bucket_name` output.
2. Migrate the bootstrap state into S3:
   ```
   terraform init -migrate-state
   ```

### First real stack: static site

```
cd stacks/static-site
```

1. Set `bucket` in `backend.tf` to your state bucket name.
2. `cp terraform.tfvars.example terraform.tfvars` and set a globally unique `site_bucket_name`.
3. `terraform init`, then let the agent run the plan-review-apply loop.
4. On success, open the `website_endpoint` output URL.

To tear it down: `terraform destroy` (the agent will show the destroy plan and ask first).

## Repository layout

```
.claude/
  settings.json            # permission guardrails: apply/destroy always prompt
  skills/provision-aws/    # the agent's operating procedure
bootstrap/                 # state bucket + AWS Budget (run once)
modules/                   # shared reusable modules
stacks/<name>/             # one directory per project, isolated state
DESIGN.md                  # full design
```

## Daily use

Start a session, make sure `aws sso login` is current, and just tell the agent what you want:
"add an SQS queue", "spin up a small VPC", "destroy the static site".
It will follow the loop in the skill.
