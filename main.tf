provider "aws" {
  region = "eu-west-1"  # Changez selon votre région
}

terraform {
  backend "s3" {
    bucket         = "terraform-backend-thomas"          # Nom de votre bucket S3
    key            = "eb-prod.state"      # Chemin du fichier d'état
    region         = "us-east-2"          # Votre région
    #dynamodb_table = "terraform-lock"     # Pour le verrouillage de l'état
    encrypt        = true                 # Chiffrement
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"  # Utilisez la version appropriée
    }
  }
}


resource "aws_s3_bucket" "eb_prod" {
  bucket = "maalshelto-eb-prod"  # Nom du bucket S3 de déploiement

  tags = {
    Name        = "maalshelto-eb-prod"
    Environment = "production"
  }
}

resource "aws_s3_bucket" "eb-artifact-store" {
  bucket = "maalshelto-eb-artifact-store"  # Nom du bucket S3 de déploiement

  tags = {
    Name        = "maalshelto-eb-artifact-store"
    Environment = "pipeline"
  }
}

resource "aws_codestarconnections_connection" "github_connection" {
  name     = "MyGitHubConnection"
  provider_type = "GitHub"  
  # Configurez ici les paramètres d'authentification pour GitHub
}


resource "aws_codepipeline" "my_pipeline" {
  name     = "EBMainPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn     

  artifact_store {
    location = "maalshelto-eb-artifact-store"  
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name            = "Source"
      category        = "Source"
      owner           = "AWS"
      provider        = "CodeStarSourceConnection"
      version         = "1"
      output_artifacts = ["SourceOutput"]

    #TODO : Variabilize Github Source Repo
      configuration = {
        Owner      = "Maalshekto"  # Remplacez par le propriétaire
        Repo       = "my-website-repo"       # Remplacez par le nom du repo
        Branch     = "master"                   # Branche source
        ConnectionArn      = aws_codestarconnections_connection.github_connection.arn
      }
    }
  }
  stage {
    name = "Deploy"
    action {
      name            = "S3Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration = {
        BucketName = aws_s3_bucket.eb_prod.bucket
        Extract    = "true"
        # ObjectKey  = "."  # Spécifiez le chemin de votre artefact
      }
    }
  }
}

data "aws_iam_policy_document" "codepipeline_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineRole"

  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role_policy.json
}

resource "aws_iam_policy" "codepipeline_s3_policy" {
  name        = "CodePipelineS3Policy"
  description = "Policy for CodePipeline to access S3"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::maalshelto-eb-artifact-store",
          "arn:aws:s3:::maalshelto-eb-artifact-store/*",
          "arn:aws:s3:::maalshelto-eb-prod",
          "arn:aws:s3:::maalshelto-eb-prod/*",
        ]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "codepipeline_s3_attachment" {
  name       = "codepipeline_s3_attachment"
  policy_arn = aws_iam_policy.codepipeline_s3_policy.arn
  roles      = [aws_iam_role.codepipeline_role.name]
}


# N'oubliez pas d'ajouter les permissions nécessaires à la role