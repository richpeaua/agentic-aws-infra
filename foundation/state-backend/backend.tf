# ---------------------------------------------------------------------------
# Remote state backend for the bootstrap stack.
#
# IMPORTANT: keep this block commented out for the FIRST apply. The state
# bucket does not exist yet, so bootstrap must run with local state.
#
# After the first successful apply creates the bucket:
#   1. Uncomment the block below.
#   2. Set `bucket` to the value of the `state_bucket_name` output.
#   3. Run: terraform init -migrate-state
#   4. Confirm the prompt to copy local state into S3.
# ---------------------------------------------------------------------------

# Partial backend configuration. The sensitive `bucket` value (it contains the
# account ID) is supplied at init time and kept out of version control:
#   terraform init -backend-config=backend.tfbackend
# The git-ignored backend.tfbackend file holds: bucket = "<state-bucket-name>"
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
