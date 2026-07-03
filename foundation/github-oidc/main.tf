provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "github-oidc"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider
#
# Lets GitHub Actions workflows assume IAM roles with short-lived credentials
# and no stored AWS keys. The thumbprint is computed dynamically from GitHub's
# OIDC endpoint so it never goes stale.
# ---------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

locals {
  repo_sub_prefix = "repo:${var.github_org}/${var.github_repo}"
}

# ---------------------------------------------------------------------------
# Trust policies
#
# Each role is assumable only via GitHub OIDC (AssumeRoleWithWebIdentity),
# scoped to this exact repo, with a distinct `sub` claim:
#   - read role:  pull_request jobs
#   - dev role:   the `dev` GitHub Environment
#   - prod role:  the `production` GitHub Environment
# The environment-scoped subs mean the apply roles cannot be assumed from a
# pull_request job or a fork.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "read_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "dev_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:environment:dev"]
    }
  }
}

data "aws_iam_policy_document" "prod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:environment:production"]
    }
  }
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "read" {
  name                 = "${var.project}-gha-read"
  description          = "GitHub Actions PR plan jobs. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.read_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "read" {
  role       = aws_iam_role.read.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role" "dev_apply" {
  name                 = "${var.project}-gha-dev-apply"
  description          = "GitHub Actions apply for the dev environment."
  assume_role_policy   = data.aws_iam_policy_document.dev_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "dev_apply" {
  role       = aws_iam_role.dev_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "prod_apply" {
  name                 = "${var.project}-gha-prod-apply"
  description          = "GitHub Actions apply for the production environment."
  assume_role_policy   = data.aws_iam_policy_document.prod_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "prod_apply" {
  role       = aws_iam_role.prod_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
