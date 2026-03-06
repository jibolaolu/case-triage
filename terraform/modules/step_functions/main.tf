################################################################################
# Step Functions Module — AI Orchestration State Machine
# Covers Layers 3–5: Tech Validation + Data Extraction (via SQS)
################################################################################

variable "prefix"                       {}
variable "step_functions_role_arn"      {}
variable "tech_validation_queue_url"    {}
variable "extraction_queue_url"         {}
variable "tech_validation_lambda_arn"   {}
variable "data_extraction_lambda_arn"   {}
variable "policy_evaluation_lambda_arn" {}
variable "case_summary_lambda_arn"      {}

# ─── CloudWatch Log Group ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/states/${var.prefix}-case-processing"
  retention_in_days = 30
}

# ─── State Machine Definition ─────────────────────────────────────────────────
# Flow:
#  START
#    → SendToTechValidationQueue (SQS)
#    → WaitForTechValidation (poll DynamoDB)
#    → CheckTechValidationResult
#    → [FAIL] → TechValidationFailed
#    → [PASS] → SendToExtractionQueue (SQS)
#    → WaitForExtraction (poll DynamoDB)
#    → CheckExtractionResult
#    → [FAIL] → ExtractionFailed
#    → [PASS] → PolicyEvaluationComplete (placeholder for Agent 3)
#    → CaseSummaryComplete (placeholder for Agent 4)
#    → READY_FOR_CASEWORKER_REVIEW
#  END

resource "aws_sfn_state_machine" "case_processing" {
  name     = "${var.prefix}-case-processing"
  role_arn = var.step_functions_role_arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Case Triage AI Orchestration — Technical Validation + Data Extraction"
    StartAt = "SendToTechValidationQueue"

    States = {

      # ── Stage 1: Technical Validation via SQS ───────────────────────────────
      "SendToTechValidationQueue" = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = var.tech_validation_queue_url
          MessageBody = {
            "caseId.$"       = "$.detail.caseId"
            "orgId.$"        = "$.detail.orgId"
            "policyVersion.$" = "$.detail.policyVersion"
            "executionId.$"  = "$$.Execution.Id"
          }
        }
        ResultPath = "$.techValidationSend"
        Next       = "WaitForTechValidation"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "TechValidationFailed"
          ResultPath  = "$.error"
        }]
      }

      # Poll DynamoDB until tech validation Lambda updates status
      "WaitForTechValidation" = {
        Type    = "Wait"
        Seconds = 15
        Next    = "CheckTechValidationStatus"
      }

      "CheckTechValidationStatus" = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = "${var.prefix}-case-runtime-state"
          Key = {
            caseId = { "S.$" = "$.detail.caseId" }
          }
        }
        ResultPath = "$.techStatusResult"
        Next       = "EvaluateTechValidationResult"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 3
          MaxAttempts     = 3
          BackoffRate     = 1.5
        }]
      }

      "EvaluateTechValidationResult" = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.techStatusResult.Item.status.S"
            StringEquals = "DOCS_TECHNICALLY_VALIDATED"
            Next         = "SendToExtractionQueue"
          },
          {
            Variable     = "$.techStatusResult.Item.status.S"
            StringEquals = "DOCS_TECHNICALLY_FAILED"
            Next         = "TechValidationFailed"
          }
        ]
        # Still processing — loop back and wait
        Default = "WaitForTechValidation"
      }

      "TechValidationFailed" = {
        Type  = "Fail"
        Error = "TechValidationFailed"
        Cause = "Document technical validation failed — case halted"
      }

      # ── Stage 2: Data Extraction via SQS ────────────────────────────────────
      "SendToExtractionQueue" = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = var.extraction_queue_url
          MessageBody = {
            "caseId.$"        = "$.detail.caseId"
            "orgId.$"         = "$.detail.orgId"
            "policyVersion.$" = "$.detail.policyVersion"
            "executionId.$"   = "$$.Execution.Id"
          }
        }
        ResultPath = "$.extractionSend"
        Next       = "WaitForExtraction"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ExtractionFailed"
          ResultPath  = "$.error"
        }]
      }

      "WaitForExtraction" = {
        Type    = "Wait"
        Seconds = 30   # Textract + LLM takes longer
        Next    = "CheckExtractionStatus"
      }

      "CheckExtractionStatus" = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = "${var.prefix}-case-runtime-state"
          Key = {
            caseId = { "S.$" = "$.detail.caseId" }
          }
        }
        ResultPath = "$.extractionStatusResult"
        Next       = "EvaluateExtractionResult"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 3
          MaxAttempts     = 3
          BackoffRate     = 1.5
        }]
      }

      "EvaluateExtractionResult" = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.extractionStatusResult.Item.status.S"
            StringEquals = "DATA_EXTRACTED"
            Next         = "PolicyEvaluation"
          },
          {
            Variable     = "$.extractionStatusResult.Item.status.S"
            StringEquals = "EXTRACTION_FAILED"
            Next         = "ExtractionFailed"
          }
        ]
        Default = "WaitForExtraction"
      }

      "ExtractionFailed" = {
        Type  = "Fail"
        Error = "ExtractionFailed"
        Cause = "Data extraction stage failed — check extraction-dlq"
      }

      # ── Stage 3: Policy Evaluation (Agent 3 placeholder) ────────────────────
      # Direct Lambda invocation — lighter workload, SQS optional at scale
      "PolicyEvaluation" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.policy_evaluation_lambda_arn
          Payload = {
            "caseId.$"        = "$.detail.caseId"
            "orgId.$"         = "$.detail.orgId"
            "policyVersion.$" = "$.detail.policyVersion"
          }
        }
        ResultPath = "$.policyResult"
        Next       = "CaseSummary"
        Retry = [{
          ErrorEquals     = ["Lambda.TooManyRequestsException", "Lambda.ServiceException"]
          IntervalSeconds = 10
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PolicyEvaluationFailed"
          ResultPath  = "$.error"
        }]
      }

      "PolicyEvaluationFailed" = {
        Type  = "Fail"
        Error = "PolicyEvaluationFailed"
        Cause = "Policy evaluation stage failed"
      }

      # ── Stage 4: Case Summary (Agent 4 placeholder) ───────────────────────
      "CaseSummary" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.case_summary_lambda_arn
          Payload = {
            "caseId.$"        = "$.detail.caseId"
            "orgId.$"         = "$.detail.orgId"
            "policyVersion.$" = "$.detail.policyVersion"
          }
        }
        ResultPath = "$.summaryResult"
        Next       = "CaseReadyForReview"
        Retry = [{
          ErrorEquals     = ["Lambda.TooManyRequestsException", "Lambda.ServiceException"]
          IntervalSeconds = 10
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "CaseSummaryFailed"
          ResultPath  = "$.error"
        }]
      }

      "CaseSummaryFailed" = {
        Type  = "Fail"
        Error = "CaseSummaryFailed"
        Cause = "Case summary generation failed"
      }

      # ── Terminal success state ────────────────────────────────────────────
      "CaseReadyForReview" = {
        Type = "Succeed"
      }

    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = false  # no PII in logs
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true  # X-Ray
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "state_machine_arn"  { value = aws_sfn_state_machine.case_processing.arn }
output "state_machine_name" { value = aws_sfn_state_machine.case_processing.name }
