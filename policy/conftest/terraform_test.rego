# Unit tests for the compliance policy. Run with:
#   conftest verify --policy policy/conftest
package main

import rego.v1

_bucket(name, tags) := {"resource_changes": [{
	"address": "aws_s3_bucket.x",
	"type": "aws_s3_bucket",
	"change": {"actions": ["create"], "after": {"bucket": name, "tags_all": tags}},
}]}

_full_tags := {"Project": "p", "Stack": "static-site", "Environment": "dev", "ManagedBy": "terraform"}

test_denies_missing_tags if {
	some msg in deny with input as _bucket("p-static-site-dev-123", {"Project": "p"})
	contains(msg, "missing required tag")
}

test_allows_fully_tagged_and_named if {
	count(deny) == 0 with input as _bucket("p-static-site-dev-123", _full_tags)
}

test_denies_bucket_without_environment if {
	some msg in deny with input as _bucket("myproject-bucket", _full_tags)
	contains(msg, "must include the environment")
}

test_warns_on_public_access if {
	some msg in warn with input as {"resource_changes": [{
		"address": "aws_s3_bucket_public_access_block.x",
		"type": "aws_s3_bucket_public_access_block",
		"change": {"actions": ["create"], "after": {"block_public_policy": false}},
	}]}
	contains(msg, "intentionally public")
}
