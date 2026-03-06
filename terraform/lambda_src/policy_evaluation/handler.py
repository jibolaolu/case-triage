"""
Agent 3: Policy Evaluation Lambda
Case Triage Management System

Evaluates extracted applicant data against policy rules for the case type.
Uses Claude via Bedrock to reason over eligibility criteria and produce
a structured decision with rule-by-rule breakdown.

Trigger: Step Functions direct Lambda invoke (after DataExtraction succeeds)
Input:  { "caseId": "...", "orgId": "...", "policyVersion": 1 }
Output: { "caseId": "...", "status": "POLICY_EVALUATED|POLICY_EVALUATION_FAILED", ... }
"""

import json
import os
import sys
import boto3
import logging
from decimal import Decimal
from datetime import datetime, timezone
from botocore.exceptions import ClientError

# agent_utils is co-deployed in the Lambda zip
sys.path.insert(0, os.path.dirname(__file__))
import agent_utils

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
bedrock  = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2"))

DYNAMODB_TABLE   = os.environ["DYNAMODB_TABLE"]
# eu-west-2 requires cross-region inference profile prefix "eu."
# Direct model IDs (without prefix) are not available as single-region in EU
BEDROCK_MODEL_ID = "anthropic.claude-3-7-sonnet-20250219-v1:0"
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


# ── Policy rule definitions per case type ─────────────────────────────────────
# These are the rules the AI evaluates against. Extend as policy evolves.
POLICY_RULES = {
    "hardship-fund": [
        {"rule_id": "HF-001", "name": "Monthly Income Threshold",    "description": "Gross monthly income must be below £2,000",                "blocking": True},
        {"rule_id": "HF-002", "name": "Savings Threshold",           "description": "Total savings must be below £3,000",                       "blocking": True},
        {"rule_id": "HF-003", "name": "Rent-to-Income Ratio",        "description": "Monthly rent should not exceed 50% of monthly income",     "blocking": False},
        {"rule_id": "HF-004", "name": "Identity Verification",       "description": "Valid UK photo ID must be present and legible",            "blocking": True},
        {"rule_id": "HF-005", "name": "3-Month Bank History",        "description": "Three consecutive months of bank statements required",     "blocking": True},
        {"rule_id": "HF-006", "name": "Residency Documentation",     "description": "Proof of UK residency required (tenancy agreement)",       "blocking": True},
    ],
    "housing-support": [
        {"rule_id": "HS-001", "name": "Income Below Threshold",      "description": "Monthly income must be below £2,500",                     "blocking": True},
        {"rule_id": "HS-002", "name": "Rent Burden",                 "description": "Rent must exceed 30% of gross monthly income",            "blocking": True},
        {"rule_id": "HS-003", "name": "Savings Check",               "description": "Savings must be below £5,000",                           "blocking": True},
        {"rule_id": "HS-004", "name": "Active Tenancy",              "description": "Valid tenancy agreement required — not owner-occupier",   "blocking": True},
        {"rule_id": "HS-005", "name": "Identity Verification",       "description": "Valid UK photo ID must be present and legible",           "blocking": True},
        {"rule_id": "HS-006", "name": "Bank Statement Coverage",     "description": "Bank statements covering last 3 months required",         "blocking": True},
        {"rule_id": "HS-007", "name": "Employment Status",           "description": "Employment status should be documented",                  "blocking": False},
    ],
    "emergency-grant": [
        {"rule_id": "EG-001", "name": "Crisis Indicator",            "description": "Evidence of acute financial crisis required",             "blocking": True},
        {"rule_id": "EG-002", "name": "Income Verification",         "description": "Current income documented — any level",                   "blocking": False},
        {"rule_id": "EG-003", "name": "Identity Verification",       "description": "Valid UK photo ID must be present and legible",           "blocking": True},
        {"rule_id": "EG-004", "name": "Bank Statement",              "description": "At least one recent bank statement required",             "blocking": True},
        {"rule_id": "EG-005", "name": "Residency Documentation",     "description": "UK address verification required",                       "blocking": True},
    ],
}

EVALUATION_PROMPT = """\
You are a policy evaluation agent for a UK government case triage system.
Your job is to evaluate whether an applicant meets the eligibility criteria for {case_type}.

EXTRACTED APPLICANT DATA:
{extracted_data}

POLICY RULES TO EVALUATE (Policy Version {policy_version}):
{rules_json}

INSTRUCTIONS:
- Evaluate each rule against the extracted data
- Be factual — only use information present in the extracted data
- If a field is null/missing, mark that rule as INCONCLUSIVE (not PASS or FAIL)
- Blocking rules that FAIL mean the application cannot proceed without caseworker override
- Non-blocking rules that FAIL generate a warning only

Return ONLY valid JSON in this exact format, no explanation:
{{
  "overall_status": "ELIGIBLE|INELIGIBLE|INCONCLUSIVE",
  "overall_rationale": "1-2 sentence summary of the overall determination",
  "rule_results": [
    {{
      "rule_id": "HF-001",
      "name": "Rule name",
      "status": "PASS|FAIL|INCONCLUSIVE",
      "rationale": "Why this rule passed or failed based on the data",
      "data_used": "Which extracted field(s) were used to evaluate this rule",
      "blocking": true
    }}
  ],
  "passed_rules": 0,
  "failed_rules": 0,
  "inconclusive_rules": 0,
  "blocking_failures": ["rule_id list of blocking failures only"],
  "warnings": ["rule_id list of non-blocking failures"],
  "caseworker_flags": ["Any specific items the caseworker should manually verify"]
}}"""


def lambda_handler(event, context):
    """
    Direct Lambda invoke from Step Functions.
    Input: { "caseId": "...", "orgId": "...", "policyVersion": 1 }
    """
    logger.info("PolicyEvaluation Lambda invoked: %s", json.dumps(event, cls=DecimalEncoder))

    case_id        = event.get("caseId")
    policy_version = int(event.get("policyVersion", 1))

    if not case_id:
        raise ValueError("Missing required field: caseId")

    table = dynamodb.Table(DYNAMODB_TABLE)

    # ── 1. Load case from DynamoDB ────────────────────────────────────────────
    try:
        result = table.get_item(Key={"caseId": case_id})
        case   = result.get("Item")
        if not case:
            raise ValueError(f"Case {case_id} not found in DynamoDB")
    except ClientError as e:
        logger.error("DynamoDB read failed: %s", e)
        raise

    case_type     = case.get("caseType", "hardship-fund")
    extracted_raw = case.get("extractedData", "{}")

    # ── 2. Idempotency check ──────────────────────────────────────────────────
    if case.get("status") == "POLICY_EVALUATED":
        logger.info("Case %s already policy-evaluated — skipping", case_id)
        return _build_response(case_id, case.get("policyResult", {}))

    # ── 3. Parse extracted data ───────────────────────────────────────────────
    try:
        extracted_data = json.loads(extracted_raw) if isinstance(extracted_raw, str) else extracted_raw
    except (json.JSONDecodeError, TypeError):
        extracted_data = {}
        logger.warning("Could not parse extractedData for case %s", case_id)

    # ── 4. Get policy rules for this case type ────────────────────────────────
    rules = POLICY_RULES.get(case_type, POLICY_RULES["hardship-fund"])
    logger.info("Evaluating case %s (%s) against %d rules", case_id, case_type, len(rules))

    # ── 5. Call Bedrock (Claude) for policy evaluation ────────────────────────
    prompt = EVALUATION_PROMPT.format(
        case_type      = case_type,
        extracted_data = json.dumps(extracted_data, indent=2, cls=DecimalEncoder)[:6000],
        policy_version = policy_version,
        rules_json     = json.dumps(rules, indent=2),
    )

    try:
        response = bedrock.invoke_model(
            modelId     = BEDROCK_MODEL_ID,
            contentType = "application/json",
            accept      = "application/json",
            body        = json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2000,
                "messages": [{"role": "user", "content": prompt}]
            })
        )
        raw_text = json.loads(response["body"].read())["content"][0]["text"].strip()

        # Strip markdown fences if present
        if raw_text.startswith("```"):
            raw_text = raw_text.split("```")[1]
            if raw_text.startswith("json"):
                raw_text = raw_text[4:]
            raw_text = raw_text.split("```")[0]

        policy_result = json.loads(raw_text.strip())
        logger.info("Policy evaluation complete for %s: %s", case_id, policy_result.get("overall_status"))

    except Exception as e:
        logger.error("Bedrock policy evaluation failed for %s: %s", case_id, e)
        # Produce an INCONCLUSIVE result rather than crashing the pipeline
        policy_result = {
            "overall_status":    "INCONCLUSIVE",
            "overall_rationale": f"Automated evaluation unavailable: {str(e)[:200]}",
            "rule_results":      [{"rule_id": r["rule_id"], "name": r["name"], "status": "INCONCLUSIVE",
                                   "rationale": "AI evaluation failed", "data_used": "N/A",
                                   "blocking": r["blocking"]} for r in rules],
            "passed_rules":       0,
            "failed_rules":       0,
            "inconclusive_rules": len(rules),
            "blocking_failures":  [],
            "warnings":           [],
            "caseworker_flags":  ["Automated policy evaluation failed — full manual review required"],
        }

    # ── 6. Determine overall status for DynamoDB ──────────────────────────────
    overall = policy_result.get("overall_status", "INCONCLUSIVE")
    has_blocking = len(policy_result.get("blocking_failures", [])) > 0
    dynamo_status = "POLICY_EVALUATION_FAILED" if has_blocking and overall == "INELIGIBLE" else "POLICY_EVALUATED"

    # ── 7. Persist result to DynamoDB ─────────────────────────────────────────
    now = datetime.now(timezone.utc).isoformat()
    try:
        table.update_item(
            Key={"caseId": case_id},
            UpdateExpression="SET #s = :status, updatedAt = :now, policyResult = :result, policyStatus = :ps",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":status": dynamo_status,
                ":now":    now,
                ":result": json.dumps(policy_result, cls=DecimalEncoder),
                ":ps":     overall,
            }
        )
        logger.info("Case %s policy status updated: %s (%s)", case_id, dynamo_status, overall)
    except ClientError as e:
        logger.error("DynamoDB update failed for %s: %s", case_id, e)
        raise

    # ── 8. Dual audit: DynamoDB audit trail + Aurora case_events ────────────────
    from_status = case.get("status", "DATA_EXTRACTED")
    agent_utils.write_audit(
        case_id     = case_id,
        agent       = "PolicyEvaluation",
        from_status = from_status,
        to_status   = dynamo_status,
        details     = {
            "overall_status":   overall,
            "passed_rules":     policy_result.get("passed_rules", 0),
            "failed_rules":     policy_result.get("failed_rules", 0),
            "blocking_failures": policy_result.get("blocking_failures", []),
        }
    )

    # ── 9. Write eval outcomes to Aurora (rule_id-safe) ───────────────────────
    # Fallback rules use string IDs (e.g. "HS-001") which are NOT UUIDs.
    # write_eval_outcomes_safe() omits the rule_id FK column when no UUID available.
    _write_eval_outcomes_safe(case_id, policy_result.get("rule_results", []))

    return _build_response(case_id, policy_result)


def _write_eval_outcomes_safe(case_id: str, rule_results: list):
    """
    Write policy evaluation outcomes to Aurora eval_outcomes table.

    FIX for SQLState 22P02: The embedded fallback POLICY_RULES dict uses
    string rule_ids (e.g. "HS-001") which are NOT UUIDs. The eval_outcomes
    table has rule_id UUID FK to policy_rules — passing a non-UUID crashes.

    Solution: use an alternative insert that uses rule_name as the identifier
    and leaves rule_id NULL (nullable FK). This avoids the type mismatch while
    still preserving evaluation results in Aurora.

    When real policy rules are seeded via Aurora, the rule_id will be a proper
    UUID and can be used directly. Check is done by trying UUID parse first.
    """
    import uuid as _uuid

    if not agent_utils.AURORA_AVAILABLE:
        return

    for rule in rule_results:
        raw_rule_id  = rule.get("rule_id", "")
        rule_name    = rule.get("name", raw_rule_id)
        result       = rule.get("status", "INCONCLUSIVE")
        explanation  = rule.get("rationale", "")
        is_blocking  = rule.get("blocking", True)

        # Determine if rule_id is a real UUID (seeded Aurora rules)
        # or a fallback string like "HS-001"
        is_real_uuid = False
        try:
            _uuid.UUID(str(raw_rule_id))
            is_real_uuid = True
        except (ValueError, AttributeError):
            is_real_uuid = False

        try:
            if is_real_uuid:
                # Real policy rule from Aurora — use rule_id FK
                agent_utils.aurora.execute("""
                    INSERT INTO eval_outcomes
                        (case_id, rule_id, result, explanation, is_blocking)
                    VALUES
                        (:case_id, :rule_id::uuid, :result, :explanation, :is_blocking)
                    ON CONFLICT (case_id, rule_id) DO UPDATE
                    SET result      = EXCLUDED.result,
                        explanation = EXCLUDED.explanation,
                        evaluated_at = NOW()
                """, [
                    agent_utils.aurora.param("case_id",     case_id),
                    agent_utils.aurora.param("rule_id",     raw_rule_id),
                    agent_utils.aurora.param("result",      result),
                    agent_utils.aurora.param("explanation", explanation),
                    agent_utils.aurora.param("is_blocking", is_blocking),
                ])
            else:
                # Fallback embedded rule — omit rule_id FK to avoid UUID cast error
                # Store rule_name in explanation prefix for traceability
                full_explanation = f"[{raw_rule_id}] {explanation}"
                agent_utils.aurora.execute("""
                    INSERT INTO eval_outcomes
                        (case_id, result, explanation, is_blocking)
                    VALUES
                        (:case_id, :result, :explanation, :is_blocking)
                """, [
                    agent_utils.aurora.param("case_id",     case_id),
                    agent_utils.aurora.param("result",      result),
                    agent_utils.aurora.param("explanation", full_explanation[:500]),
                    agent_utils.aurora.param("is_blocking", is_blocking),
                ])
        except Exception as e:
            import logging as _log
            _log.getLogger().warning(
                "Aurora eval_outcomes write failed for rule %s (non-fatal): %s",
                raw_rule_id, e
            )


def _build_response(case_id, policy_result):
    return {
        "caseId":           case_id,
        "status":           policy_result.get("overall_status", "INCONCLUSIVE"),
        "passedRules":      policy_result.get("passed_rules", 0),
        "failedRules":      policy_result.get("failed_rules", 0),
        "blockingFailures": policy_result.get("blocking_failures", []),
        "warnings":         policy_result.get("warnings", []),
        "rationale":        policy_result.get("overall_rationale", ""),
    }
