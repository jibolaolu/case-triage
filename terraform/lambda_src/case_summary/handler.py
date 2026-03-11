"""
lambda_src/case_summary/handler.py  (UPDATED)

Agent 4 — CaseSummary
Step Functions direct Lambda invoke

CHANGES FROM ORIGINAL:
  + write_case_summary_aurora() persists final summary to Aurora case_summaries
  + write_audit() on every status change — completes the full audit trail
  + BEDROCK_MODEL_ID from env var
"""

import json
import os
import sys
import boto3
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError

sys.path.insert(0, os.path.dirname(__file__))
from agent_utils import (
    get_case, update_status, write_audit,
    write_case_summary_aurora, DecimalEncoder, AURORA_READY
)

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_region   = os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2")
s3        = boto3.client("s3")
bedrock   = boto3.client("bedrock-runtime", region_name=_region)

DOCUMENTS_BUCKET = os.environ["DOCUMENTS_BUCKET"]
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID", "anthropic.claude-3-7-sonnet-20250219-v1:0"
)
CASE_PACK_PREFIX = "case-packs"

SUMMARY_PROMPT = """\
You are a senior caseworker assistant for a UK government case triage system.
Synthesize AI findings into a clear, actionable summary for human caseworkers.

CASE: {case_id} | Type: {case_type} | Org: {org_id} | Policy v{policy_version}

AGENT 2 — DATA EXTRACTION:
{extracted_data}

AGENT 3 — POLICY EVALUATION:
Overall: {policy_status}
Passed: {passed} | Failed: {failed}
Blocking failures: {blocking}
Warnings: {warnings}
Rationale: {rationale}

CRITICAL: Do NOT make the final approval/denial decision — synthesize only.
Return ONLY valid JSON:
{{
  "case_summary": {{
    "applicant_overview": "2-3 sentences on applicant situation",
    "key_findings": ["3-5 most important findings"],
    "technical_assessment": "Plain language doc quality summary",
    "policy_compliance": "Clear explanation of policy evaluation",
    "concerns": ["Red flags — empty array if none"],
    "strengths": ["Positive factors"]
  }},
  "recommendation": {{
    "priority_level": "HIGH|MEDIUM|LOW",
    "priority_rationale": "Why this priority",
    "suggested_next_action": "Specific caseworker action",
    "estimated_decision_complexity": "STRAIGHTFORWARD|MODERATE|COMPLEX",
    "requires_supervisor_review": false,
    "supervisor_review_reason": null
  }},
  "data_quality_assessment": {{
    "overall_confidence": "HIGH|MEDIUM|LOW",
    "extraction_reliability": "Assessment of data reliability",
    "missing_or_unclear_information": ["Gaps or ambiguities"]
  }},
  "caseworker_notes": [
    "Specific actionable notes",
    "Follow-up questions",
    "Verification steps"
  ]
}}"""


def lambda_handler(event, context):
    logger.info("CaseSummary invoked: %s", json.dumps(event, cls=DecimalEncoder))

    case_id = event.get("caseId")
    if not case_id:
        raise ValueError("Missing caseId")

    case = get_case(case_id)
    if not case:
        raise ValueError(f"Case {case_id} not found")

    current_status = case.get("status", "")

    if current_status == "READY_FOR_CASEWORKER_REVIEW":
        logger.info("Case %s already summarised — skipping", case_id)
        return {"caseId": case_id, "status": "READY_FOR_CASEWORKER_REVIEW",
                "message": "Already processed"}

    def safe_json(v):
        if isinstance(v, (dict, list)):
            return v
        try:
            return json.loads(v) if v else {}
        except Exception:
            return {}

    extracted  = safe_json(case.get("extractedData", "{}"))
    policy_res = safe_json(case.get("policyResult", "{}"))
    case_type  = case.get("caseType", "unknown")
    org_id     = case.get("orgId", "unknown")

    # ── Generate AI summary via Bedrock ──────────────────────────────────────
    summary = _generate_summary(case_id, case_type, org_id, case, extracted, policy_res)

    # ── Build and save case pack to S3 ────────────────────────────────────────
    case_pack    = _build_pack(case_id, case, extracted, policy_res, summary)
    s3_key       = _save_pack(case_id, case_pack)

    priority   = summary.get("recommendation", {}).get("priority_level", "MEDIUM")
    needs_sup  = summary.get("recommendation", {}).get("requires_supervisor_review", False)

    # ── Update DynamoDB runtime state ─────────────────────────────────────────
    confidence_level = summary.get("data_quality_assessment", {}).get("overall_confidence", "")
    ai_confidence_score = {"LOW": 25, "MEDIUM": 60, "HIGH": 90}.get(confidence_level)

    update_status(case_id, "READY_FOR_CASEWORKER_REVIEW", {
        "caseSummary": json.dumps(summary, cls=DecimalEncoder),
        "casePackS3Key": s3_key or "",
        "priority": priority,
        "requiresSupervisorReview": needs_sup,
        "aiConfidence": ai_confidence_score,
    })

    # ── Write to Aurora case_summaries table (NEW) ────────────────────────────
    summary["model_used"] = BEDROCK_MODEL_ID
    write_case_summary_aurora(case_id, summary)

    # ── Write audit event — closes the full audit trail (NEW) ─────────────────
    write_audit(
        case_id     = case_id,
        agent       = "CaseSummary",
        from_status = current_status,
        to_status   = "READY_FOR_CASEWORKER_REVIEW",
        details     = {
            "priority":           priority,
            "requires_supervisor": needs_sup,
            "s3_key":             s3_key,
            "model":              BEDROCK_MODEL_ID,
            "aurora_written":     AURORA_READY,
        }
    )

    logger.info("CaseSummary complete for %s → READY_FOR_CASEWORKER_REVIEW "
                "(priority: %s)", case_id, priority)

    return {
        "caseId":                    case_id,
        "status":                    "READY_FOR_CASEWORKER_REVIEW",
        "priority":                  priority,
        "requiresSupervisorReview":  needs_sup,
        "casePackS3Key":             s3_key,
        "suggestedNextAction":       summary.get("recommendation", {}).get(
                                       "suggested_next_action", ""),
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _generate_summary(case_id, case_type, org_id, case, extracted, pr):
    prompt = SUMMARY_PROMPT.format(
        case_id        = case_id,
        case_type      = case_type,
        org_id         = org_id,
        policy_version = case.get("policyVersion", 1),
        extracted_data = json.dumps(extracted, indent=2, cls=DecimalEncoder)[:4000],
        policy_status  = pr.get("overall_status", "INCONCLUSIVE"),
        passed         = pr.get("passed_rules", "?"),
        failed         = pr.get("failed_rules", "?"),
        blocking       = json.dumps(pr.get("blocking_failures", []), cls=DecimalEncoder),
        warnings       = json.dumps(pr.get("warnings", []), cls=DecimalEncoder),
        rationale      = pr.get("overall_rationale", "No rationale available"),
    )

    try:
        resp = bedrock.invoke_model(
            modelId     = BEDROCK_MODEL_ID,
            contentType = "application/json",
            accept      = "application/json",
            body        = json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 3000,
                "temperature": 0.2,
                "messages": [{"role": "user", "content": prompt}]
            })
        )
        raw = json.loads(resp["body"].read())["content"][0]["text"].strip()
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
            raw = raw.split("```")[0]

        out = json.loads(raw.strip())
        out["generated_at"] = datetime.now(timezone.utc).isoformat()
        out["generated_by"] = "Agent4-CaseSummary"
        return out

    except Exception as e:
        logger.error("Bedrock summary failed for %s: %s", case_id, e)
        return _fallback(case_id, case_type, e)


def _fallback(case_id, case_type, error):
    return {
        "case_summary": {
            "applicant_overview": f"Case {case_id} ({case_type}) — AI summary unavailable.",
            "key_findings": ["AI summary generation failed — manual review required"],
            "technical_assessment": "See CloudWatch logs",
            "policy_compliance": "See CloudWatch logs",
            "concerns": ["Automated summary unavailable"],
            "strengths": [],
        },
        "recommendation": {
            "priority_level": "HIGH",
            "priority_rationale": "AI processing incomplete",
            "suggested_next_action": "Full manual caseworker review required",
            "estimated_decision_complexity": "COMPLEX",
            "requires_supervisor_review": True,
            "supervisor_review_reason": "AI summary generation failed",
        },
        "data_quality_assessment": {
            "overall_confidence": "LOW",
            "extraction_reliability": "Cannot assess",
            "missing_or_unclear_information": ["Complete manual review required"],
        },
        "caseworker_notes": [
            "AI summary generation encountered an error — review all agent outputs manually.",
            f"Error: {str(error)[:300]}",
        ],
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generated_by": "Agent4-CaseSummary-Fallback",
        "error": str(error)[:500],
    }


def _build_pack(case_id, case, extracted, pr, summary):
    return {
        "case_id":       case_id,
        "generated_at":  datetime.now(timezone.utc).isoformat(),
        "case_info": {
            "case_type":      case.get("caseType"),
            "org_id":         case.get("orgId"),
            "policy_version": int(case.get("policyVersion", 1)),
            "submission_date": case.get("createdAt"),
        },
        "ai_processing": {
            "data_extraction":   {"extracted_fields": extracted},
            "policy_evaluation": {
                "status":           pr.get("overall_status"),
                "passed_rules":     pr.get("passed_rules", 0),
                "failed_rules":     pr.get("failed_rules", 0),
                "blocking_failures": pr.get("blocking_failures", []),
                "rule_results":     pr.get("rule_results", []),
                "caseworker_flags": pr.get("caseworker_flags", []),
            },
        },
        "summary":  summary,
        "workflow": {
            "current_stage":       "READY_FOR_CASEWORKER_REVIEW",
            "next_action":         summary.get("recommendation", {}).get("suggested_next_action"),
            "priority":            summary.get("recommendation", {}).get("priority_level"),
            "requires_supervisor": summary.get("recommendation", {}).get("requires_supervisor_review"),
        },
    }


def _save_pack(case_id, pack):
    key = f"{CASE_PACK_PREFIX}/{case_id}/case_pack.json"
    try:
        s3.put_object(
            Bucket=DOCUMENTS_BUCKET, Key=key,
            Body=json.dumps(pack, indent=2, cls=DecimalEncoder),
            ContentType="application/json",
            ServerSideEncryption="AES256",
        )
        logger.info("Case pack saved: s3://%s/%s", DOCUMENTS_BUCKET, key)
        return key
    except ClientError as e:
        logger.error("S3 case pack save failed for %s: %s", case_id, e)
        return None
