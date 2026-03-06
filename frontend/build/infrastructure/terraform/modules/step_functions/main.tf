resource "aws_iam_role" "sfn" {
  name = "${var.name_prefix}-step-functions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.name_prefix}-sfn-lambda"
  role   = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = concat(values(var.lambda_arns), [var.failure_handler_arn])
    }]
  })
}

resource "aws_sfn_state_machine" "ai_orchestration" {
  name       = "${var.name_prefix}-ai-orchestration"
  role_arn   = aws_iam_role.sfn.arn
  type       = "STANDARD"
  tracing_configuration {
    enabled = true
  }
  definition = jsonencode({
    Comment = "FastStart AI Orchestration"
    StartAt = "ValidateDocuments"
    States = {
      ValidateDocuments = {
        Type     = "Task"
        Resource = var.lambda_arns.document_validation
        TimeoutSeconds = 300
        Retry = [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 2, MaxAttempts = 3, BackoffRate = 2 }]
        Catch = [{ ErrorEquals = ["States.ALL"], Next = "PassValidateFailure", ResultPath = "$.error" }]
        Next = "ExtractData"
      }
      PassValidateFailure = {
        Type = "Pass"
        Parameters = {
          "detail.$" = "$.detail"
          "failedState" = "ValidateDocuments"
          "error.$" = "$.error"
        }
        Next = "HandleFailure"
      }
      ExtractData = {
        Type     = "Task"
        Resource = var.lambda_arns.data_extraction
        TimeoutSeconds = 900
        Retry = [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 5, MaxAttempts = 3, BackoffRate = 2 }]
        Catch = [{ ErrorEquals = ["States.ALL"], Next = "PassExtractFailure", ResultPath = "$.error" }]
        Next = "EvaluatePolicy"
      }
      PassExtractFailure = {
        Type = "Pass"
        Parameters = {
          "detail.$" = "$.detail"
          "failedState" = "ExtractData"
          "error.$" = "$.error"
        }
        Next = "HandleFailure"
      }
      EvaluatePolicy = {
        Type     = "Task"
        Resource = var.lambda_arns.policy_evaluation
        TimeoutSeconds = 300
        Retry = [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 2, MaxAttempts = 3 }]
        Catch = [{ ErrorEquals = ["States.ALL"], Next = "PassEvaluateFailure", ResultPath = "$.error" }]
        Next = "GenerateSummary"
      }
      PassEvaluateFailure = {
        Type = "Pass"
        Parameters = {
          "detail.$" = "$.detail"
          "failedState" = "EvaluatePolicy"
          "error.$" = "$.error"
        }
        Next = "HandleFailure"
      }
      GenerateSummary = {
        Type     = "Task"
        Resource = var.lambda_arns.case_summary
        TimeoutSeconds = 300
        Retry = [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 2, MaxAttempts = 3 }]
        Catch = [{ ErrorEquals = ["States.ALL"], Next = "PassSummaryFailure", ResultPath = "$.error" }]
        Next = "MarkReadyForReview"
      }
      PassSummaryFailure = {
        Type = "Pass"
        Parameters = {
          "detail.$" = "$.detail"
          "failedState" = "GenerateSummary"
          "error.$" = "$.error"
        }
        Next = "HandleFailure"
      }
      MarkReadyForReview = {
        Type     = "Task"
        Resource = var.update_case_status_arn
        Parameters = {
          "caseId.$" = "$.detail.caseId"
          "orgId.$" = "$.detail.orgId"
        }
        End = true
      }
      HandleFailure = {
        Type     = "Task"
        Resource = var.failure_handler_arn
        Parameters = {
          "caseId.$" = "$.detail.caseId"
          "orgId.$" = "$.detail.orgId"
          "failedState.$" = "$.failedState"
          "error.$" = "$.error"
        }
        End = true
      }
    }
  })
  tags = { Name = "${var.name_prefix}-ai-orchestration" }
}
