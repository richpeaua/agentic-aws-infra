# Compliance policy for Terraform plans (the custom "our rules" layer).
# Run against a plan JSON:
#   terraform show -json tfplan > plan.json
#   conftest test plan.json --policy policy/conftest
package main

import rego.v1

required_tags := {"Project", "Stack", "Environment", "ManagedBy"}

# Resources being created or updated (ignore pure deletes).
changed contains r if {
	some r in input.resource_changes
	r.change.actions[_] != "delete"
}

# Every taggable resource must carry the required tags. With provider
# default_tags these appear in tags_all.
deny contains msg if {
	some r in changed
	r.change.after.tags_all
	some t in required_tags
	not r.change.after.tags_all[t]
	msg := sprintf("%s (%s): missing required tag %q", [r.address, r.type, t])
}

# S3 bucket names must include the environment to avoid dev/prod collisions in
# the shared account.
deny contains msg if {
	some r in changed
	r.type == "aws_s3_bucket"
	name := r.change.after.bucket
	is_string(name)
	not contains(name, "-dev-")
	not contains(name, "-prod-")
	msg := sprintf("%s: S3 bucket name %q must include the environment (-dev- or -prod-)", [r.address, name])
}

# Warn when a bucket's public access is being opened. Public buckets are allowed
# only when intentional; this surfaces them for explicit confirmation in review.
warn contains msg if {
	some r in changed
	r.type == "aws_s3_bucket_public_access_block"
	r.change.after.block_public_policy == false
	msg := sprintf("%s: public access is being allowed; confirm this bucket is intentionally public", [r.address])
}
