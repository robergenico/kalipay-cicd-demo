terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = "eu-west-3" # AWS Paris (livrable 10)
}

variable "github_repo" {
  description = "Dépôt autorisé à déployer, au format owner/nom"
  type        = string
}

# --- Fédération OIDC : la CI n'a plus aucune clé AWS permanente (E6, flux F10) ---

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
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
    # Seul l'environnement « production » du dépôt peut prendre ce rôle,
    # donc seulement après la validation par un second approbateur.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:production"]
    }
  }
}

resource "aws_iam_role" "ci_deploy" {
  name                 = "kalipay-ci-deploy"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600
}

# Moindre privilège : le pipeline peut seulement décrire le cluster EKS de Z1
# pour obtenir un accès Kubernetes ; les droits dans le cluster sont donnés par RBAC.
data "aws_iam_policy_document" "ci_deploy" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:eu-west-3:*:cluster/kalipay-z1"]
  }
}

resource "aws_iam_role_policy" "ci_deploy" {
  name   = "eks-describe-z1"
  role   = aws_iam_role.ci_deploy.id
  policy = data.aws_iam_policy_document.ci_deploy.json
}

# --- Stockage des SBOM et rapports de scan, chiffré et non effaçable (E9) ---

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_artefacts" {
  # Dans une politique de clé KMS, « Resource = * » désigne la clé elle-même :
  #checkov:skip=CKV_AWS_356:Resource * limité à cette clé par nature (politique de clé KMS)
  #checkov:skip=CKV_AWS_111:Resource * limité à cette clé par nature (politique de clé KMS)
  #checkov:skip=CKV_AWS_109:Resource * limité à cette clé par nature (politique de clé KMS)
  statement {
    sid       = "AdministrationParLeCompte"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "artefacts" {
  description         = "Chiffrement des artefacts CI/CD"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_artefacts.json
}

resource "aws_s3_bucket" "artefacts" {
  # Exceptions justifiées, relues en PR comme le reste du code :
  #checkov:skip=CKV_AWS_144:La copie hors région est assurée par la sauvegarde externe Z10 (condition 4 du comité)
  #checkov:skip=CKV_AWS_18:Les accès sont tracés par les événements de données CloudTrail, envoyés au SIEM (Z7)
  #checkov:skip=CKV2_AWS_62:Les alertes passent par CloudTrail et le SIEM, pas par des notifications S3
  bucket              = "kalipay-ci-artefacts"
  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "artefacts" {
  bucket                  = aws_s3_bucket.artefacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artefacts.arn
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

# Les rapports sont gardés 12 mois puis supprimés, comme les journaux (E9)
resource "aws_s3_bucket_lifecycle_configuration" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id
  rule {
    id     = "retention-12-mois"
    status = "Enabled"
    filter {}
    expiration {
      days = 400
    }
    noncurrent_version_expiration {
      noncurrent_days = 400
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
