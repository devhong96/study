# ============================================================
# 이 파일: CI/CD 파이프라인 (Source → Build → Deploy)
# 그림의 핵심: git push 한 번으로 빌드~배포가 자동으로 흐른다.
# ============================================================

# 단계 사이에 산출물(아티팩트)을 주고받는 S3 버킷
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # 학습용: 내용 있어도 destroy
}

# GitHub 연결 (CodeStar Connections v2)
# ※ apply 후 AWS 콘솔에서 한 번 "수동 승인"해야 PENDING→AVAILABLE이 됨 (OAuth 핸드셰이크)
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-gh"
  provider_type = "GitHub"
}

# ── CodeBuild: 도커 빌드 + ECR push ──
resource "aws_codebuild_project" "build" {
  name         = "${var.project_name}-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE" # 파이프라인이 산출물을 관리
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker build 하려면 필수 (Docker-in-Docker)

    environment_variable {
      name  = "ECR_REPO"
      value = aws_ecr_repository.app.repository_url
    }
    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.project_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml" # 소스 루트의 빌드 명세 파일
  }
}

# ── CodePipeline: 전체 흐름 오케스트레이터 ──
resource "aws_codepipeline" "pipeline" {
  name     = var.project_name
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # ① Source: GitHub에서 코드 인출
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  # ② Build: CodeBuild로 도커 빌드 → ECR push → imagedefinitions.json 생성
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  # ③ Deploy: ECS 서비스에 새 이미지로 롤링 배포
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.app.name
        FileName    = "imagedefinitions.json" # buildspec이 만든 파일
      }
    }
  }
}
