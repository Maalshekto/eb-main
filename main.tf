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
}


resource "aws_s3_bucket" "eb_prod" {
  bucket = "maalshelto-eb-prod"  # Nom du bucket S3 de déploiement

  tags = {
    Name        = "maalshelto-eb-prod"
    Environment = "production"
  }
}

resource "aws_s3_bucket_public_access_block" "eb_prod_block" {
  bucket = aws_s3_bucket.eb_prod.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "eb_prod_website" {
  bucket = aws_s3_bucket.eb_prod.id

  index_document {
    suffix = "index.html"  # Page d'accueil
  }

  error_document {
    key = "error.html"  # Page d'erreur
  }
}

resource "aws_s3_bucket_policy" "eb_prod_policy" {
  bucket = aws_s3_bucket.eb_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.eb_prod.arn}/*"
      }
    ]
  })
}


resource "aws_s3_bucket" "eb-artifact-store" {
  bucket = "maalshelto-eb-artifact-store"  # Nom du bucket S3 de déploiement

  tags = {
    Name        = "maalshelto-eb-artifact-store"
    Environment = "pipeline"
  }
}

resource "aws_codestarconnections_connection" "github_connection" {
  name     = "EBProdGitHubConnection"
  provider_type = "GitHub"  
}


resource "aws_codepipeline" "my_pipeline" {
  name     = "EBMainPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn     
  pipeline_type = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    location = "maalshelto-eb-artifact-store"  
    type     = "S3"
  }
  trigger {
    provider_type = "CodeStarSourceConnection"
    
    git_configuration {
        source_action_name = "Source"
        push {
        #  branches {
        #    includes = [ "master" ]
        #  }  
        }
    }
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
        FullRepositoryId    = "maalshekto/my-website-repo"       # Remplacez par le nom du repo
        BranchName          = "master"                   # Branche source
        ConnectionArn       = aws_codestarconnections_connection.github_connection.arn        
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges = "true"
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
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::maalshelto-eb-artifact-store",
          "arn:aws:s3:::maalshelto-eb-artifact-store/*",
          "arn:aws:s3:::maalshelto-eb-prod",
          "arn:aws:s3:::maalshelto-eb-prod/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection",
          "codestar-connections:GetConnection"
        ]
        Resource = aws_codestarconnections_connection.github_connection.arn
      },
      {
        Effect = "Allow"
        Action =  [                
          "cloudwatch:*",
        ]
        Resource =  "*"      
      },
    ]
  })
}



resource "aws_iam_policy_attachment" "codepipeline_s3_attachment" {
  name       = "codepipeline_s3_attachment"
  policy_arn = aws_iam_policy.codepipeline_s3_policy.arn
  roles      = [aws_iam_role.codepipeline_role.name]
}


# N'oubliez pas d'ajouter les permissions nécessaires à la role