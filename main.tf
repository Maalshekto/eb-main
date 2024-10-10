provider "aws" {
  region = "eu-west-1"  # Changez selon votre région
}

resource "aws_s3_bucket" "eb_prod" {
  bucket = "eb-prod"  # Nom du bucket S3 de déploiement

  tags = {
    Name        = "eb-prod"
    Environment = "production"
  }
}

resource "aws_codepipeline" "my_pipeline" {
  name     = "EBMainPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = "eb-artifact-store"  
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name            = "GitHub"
      category        = "Source"
      owner           = "ThirdParty"
      provider        = "GitHub"
      version         = "1"
      output_artifacts = ["SourceOutput"]

    #TODO : Variabilize Github Source Repo
      configuration = {
        Owner      = "Maalshekto"  # Remplacez par le propriétaire
        Repo       = "my-website-repo"       # Remplacez par le nom du repo
        Branch     = "main"                   # Branche source
        OAuthToken = var.github_token          # Token GitHub
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
        ObjectKey  = "path/to/deployment.zip"  # Spécifiez le chemin de votre artefact
      }
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# N'oubliez pas d'ajouter les permissions nécessaires à la role