locals {
  # Base name for this stack's resources. Include the environment to avoid
  # collisions between dev and prod in the shared account.
  name = "${var.project}-${var.stack}-${var.environment}"
}

# TODO: define the __STACK__ resources here.
#
# Naming: use local.name as the base. For globally-unique names (for example an
# S3 bucket) append the account ID: "${local.name}-${var.account_id}".
#
# Tagging: do NOT add a provider block or default_tags here. The root supplies
# the provider and default_tags (Project, Stack, Environment, ManagedBy), which
# flow to every resource in this module automatically.
