"""
Shared utilities for all Case Triage agent Lambdas.
Provides:
  - AuroraClient   : thin wrapper around RDS Data API
  - write_audit    : append event to DynamoDB audit trail
  - update_status  : update DynamoDB runtime state + write audit event

FIX LOG:
  v2 - write_case_to_aurora: removed policy_id FK (causes constraint failure
       when no policy row exists). policy_id is now left NULL until policies
       are seeded. Added write_case_event_to_aurora for Step-Functions-free
       workflow tracing via Aurora case_events table.
"""

import json
import os
import time
import boto3
import logging
from datetime import datetime, timezone

logger = logging.getLogger()

# ─── Clients ──────────────────────────────────────────────────────────────────

_region    = os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2")
dynamodb   = boto3.resource("dynamodb", region_name=_region)
rds_data   = boto3.client("rds-data", region_name=_region)

DYNAMODB_TABLE     = os.environ.get("DYNAMODB_TABLE", "")
AUDIT_TRAIL_TABLE  = os.environ.get("AUDIT_TRAIL_TABLE", "")
AURORA_CLUSTER_ARN = os.environ.get("AURORA_CLUSTER_ARN", "")
AURORA_SECRET_ARN  = os.environ.get("AURORA_SECRET_ARN", "")
AURORA_DATABASE    = os.environ.get("AURORA_DATABASE", "case_triage")

AURORA_AVAILABLE = bool(AURORA_CLUSTER_ARN and AURORA_SECRET_ARN)


# ─── Aurora RDS Data API wrapper ─────────────────────────────────────────────

class AuroraClient:
    """Thin wrapper around RDS Data API with parameter binding."""

    def execute(self, sql: str, params: list = None) -> dict:
        """Execute a single SQL statement."""
        kwargs = {
            "resourceArn": AURORA_CLUSTER_ARN,
            "secretArn":   AURORA_SECRET_ARN,
            "database":    AURORA_DATABASE,
            "sql":         sql,
        }
        if params:
            kwargs["parameters"] = params
        return rds_data.execute_statement(**kwargs)

    def query(self, sql: str, params: list = None) -> list:
        """Execute SELECT and return list of dicts."""
        response = self.execute(sql, params)
        columns  = [col["name"] for col in response.get("columnMetadata", [])]
        rows     = []
        for row in response.get("records", []):
            record = {}
            for col, field in zip(columns, row):
                val = next(iter(field.values())) if field else None
                record[col] = val
            rows.append(record)
        return rows

    def query_one(self, sql: str, params: list = None):
        rows = self.query(sql, params)
        return rows[0] if rows else None

    @staticmethod
    def param(name: str, value, type_hint: str = None) -> dict:
        """Build an RDS Data API parameter."""
        if value is None:
            return {"name": name, "value": {"isNull": True}}
        if isinstance(value, bool):
            return {"name": name, "value": {"booleanValue": value}}
        if isinstance(value, int):
            return {"name": name, "value": {"longValue": value}}
        if isinstance(value, float):
            return {"name": name, "value": {"doubleValue": value}}
        if isinstance(value, (dict, list)):
            return {"name": name, "value": {"stringValue": json.dumps(value)},
                    "typeHint": "JSON"}
        return {"name": name, "value": {"stringValue": str(value)}}


aurora = AuroraClient()


# ─── DynamoDB helpers ─────────────────────────────────────────────────────────

def update_status(case_id: str, new_status: str, extra: dict = None):
    """Update runtime state table with new status."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    now   = datetime.now(timezone.utc).isoformat()

    update_expr  = "SET #s = :status, updatedAt = :now"
    expr_names   = {"#s": "status"}
    expr_values  = {":status": new_status, ":now": now}

    if extra:
        for k, v in extra.items():
            update_expr += f", {k} = :{k}"
            expr_values[f":{k}"] = v

    table.update_item(
        Key={"caseId": case_id},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )


def write_audit(case_id: str, agent: str, from_status: str,
                to_status: str, details: dict = None):
    """
    Dual-write audit trail:
      1. DynamoDB case-audit-trail table (immediate, always)
      2. Aurora case_events table (authoritative, non-fatal)
    """
    now     = datetime.now(timezone.utc).isoformat()
    ttl_val = int(time.time()) + (7 * 365 * 24 * 3600)

    # ── Write 1: DynamoDB audit trail ─────────────────────────────────────────
    if AUDIT_TRAIL_TABLE:
        try:
            table = dynamodb.Table(AUDIT_TRAIL_TABLE)
            table.put_item(Item={
                "caseId":     case_id,
                "eventAt":    now,
                "agent":      agent,
                "fromStatus": from_status,
                "toStatus":   to_status,
                "details":    json.dumps(details or {}),
                "expiresAt":  ttl_val,
            })
            logger.info("Audit: [%s] %s → %s", agent, from_status, to_status)
        except Exception as e:
            logger.error("DynamoDB audit write failed: %s", e)
    else:
        logger.warning("AUDIT_TRAIL_TABLE not set — skipping DynamoDB audit write")

    # ── Write 2: Aurora case_events (workflow trace — replaces Step Functions) ─
    write_case_event_to_aurora(case_id, agent, from_status, to_status, details)


def write_case_event_to_aurora(case_id: str, agent: str, from_status: str,
                                to_status: str, details: dict = None):
    """
    Write a workflow event to Aurora case_events table.
    This is the primary mechanism for tracking workflow progress
    without Step Functions — query this table to see every
    stage transition for any case.
    Non-fatal: will not fail the Lambda if Aurora is unavailable.
    """
    if not AURORA_AVAILABLE:
        return
    try:
        aurora.execute("""
            INSERT INTO case_events
                (case_id, event_type, from_status, to_status, agent, details)
            VALUES
                (:case_id, 'STATUS_CHANGE', :from_status, :to_status,
                 :agent, :details::jsonb)
        """, [
            aurora.param("case_id",     case_id),
            aurora.param("from_status", from_status),
            aurora.param("to_status",   to_status),
            aurora.param("agent",       agent),
            aurora.param("details",     json.dumps(details or {})),
        ])
    except Exception as e:
        logger.warning("Aurora case_events write failed (non-fatal): %s", e)


def get_case_status(case_id: str) -> str:
    """Read current status from runtime state table."""
    table  = dynamodb.Table(DYNAMODB_TABLE)
    result = table.get_item(Key={"caseId": case_id})
    return result.get("Item", {}).get("status", "")


# ─── Aurora helpers ───────────────────────────────────────────────────────────

def get_active_policy_rules(org_id: str, case_type: str) -> list:
    """
    Fetch policy rules for the active policy version.
    Falls back to empty list if Aurora not configured or no rules exist.
    """
    if not AURORA_AVAILABLE:
        logger.warning("Aurora not configured — returning empty rules")
        return []

    try:
        sql = """
            SELECT pr.rule_id, pr.rule_name, pr.field_name,
                   pr.operator, pr.comparison_value, pr.is_blocking,
                   pr.sort_order
            FROM policy_rules pr
            JOIN policies p ON pr.policy_id = p.policy_id
            WHERE p.org_id = :org_id
              AND p.case_type = :case_type
              AND p.status = 'active'
            ORDER BY pr.sort_order ASC
        """
        rules = aurora.query(sql, [
            aurora.param("org_id",    org_id),
            aurora.param("case_type", case_type),
        ])
        logger.info("Loaded %d policy rules from Aurora for %s/%s",
                    len(rules), org_id, case_type)
        return rules
    except Exception as e:
        logger.error("Failed to load Aurora policy rules: %s", e)
        return []


def write_case_to_aurora(case_id: str, org_id: str, case_type: str,
                          policy_version: int):
    """
    Write authoritative case record to Aurora cases table.

    FIX: policy_id column is omitted — it is a UUID FK to policies table
    which may not have a matching row yet. Leaving it NULL avoids the FK
    constraint violation seen in logs:
      ERROR: relation "cases" insert FK violation on policy_id
    Once policies are seeded per org/case_type, a separate migration can
    back-fill policy_id using:
      UPDATE cases c SET policy_id = p.policy_id
      FROM policies p
      WHERE p.org_id = c.organisation_id
        AND p.case_type = c.case_type
        AND p.status = 'active';
    """
    if not AURORA_AVAILABLE:
        return

    try:
        aurora.execute("""
            INSERT INTO cases
                (case_id, organisation_id, case_type, policy_version, submission_type)
            VALUES
                (:case_id, :org_id, :case_type, :policy_version, 'NEW')
            ON CONFLICT (case_id) DO NOTHING
        """, [
            aurora.param("case_id",        case_id),
            aurora.param("org_id",         org_id),
            aurora.param("case_type",      case_type),
            aurora.param("policy_version", policy_version),
        ])
        logger.info("Aurora: case %s written to cases table", case_id)
    except Exception as e:
        logger.warning("Aurora case write failed (non-fatal): %s", e)


def write_validation_results_to_aurora(case_id: str, doc_results: list):
    """
    Write per-document validation results to Aurora validation_results table.
    doc_results: list of dicts with keys: document_type, is_valid,
                 file_size_bytes, mime_type, failure_reason
    """
    if not AURORA_AVAILABLE:
        return

    for doc in doc_results:
        try:
            aurora.execute("""
                INSERT INTO validation_results
                    (case_id, document_type, is_valid,
                     file_size_bytes, mime_type, failure_reason)
                VALUES
                    (:case_id, :document_type, :is_valid,
                     :file_size_bytes, :mime_type, :failure_reason)
                ON CONFLICT (case_id, document_type) DO UPDATE
                SET is_valid        = EXCLUDED.is_valid,
                    failure_reason  = EXCLUDED.failure_reason,
                    validated_at    = NOW()
            """, [
                aurora.param("case_id",         case_id),
                aurora.param("document_type",   doc.get("document_type", "")),
                aurora.param("is_valid",         doc.get("is_valid", False)),
                aurora.param("file_size_bytes",  doc.get("file_size_bytes", 0)),
                aurora.param("mime_type",        doc.get("mime_type", "")),
                aurora.param("failure_reason",   doc.get("failure_reason")),
            ])
        except Exception as e:
            logger.warning("Aurora validation_results write failed (non-fatal): %s", e)


def write_extracted_data_to_aurora(case_id: str, extracted: dict):
    """Write extracted fields to Aurora extracted_data table."""
    if not AURORA_AVAILABLE:
        return

    for field_name, field_value in extracted.items():
        if field_name == "error":
            continue
        try:
            aurora.execute("""
                INSERT INTO extracted_data
                    (case_id, field_name, field_value, confidence)
                VALUES
                    (:case_id, :field_name, :field_value, :confidence)
                ON CONFLICT (case_id, field_name) DO UPDATE
                SET field_value  = EXCLUDED.field_value,
                    extracted_at = NOW()
            """, [
                aurora.param("case_id",    case_id),
                aurora.param("field_name", field_name),
                aurora.param("field_value",
                             str(field_value) if field_value is not None else None),
                aurora.param("confidence", 0.85),
            ])
        except Exception as e:
            logger.warning("Aurora extracted_data write failed (non-fatal): %s", e)


def write_eval_outcomes_to_aurora(case_id: str, results: list):
    """Write policy evaluation outcomes to Aurora eval_outcomes table."""
    if not AURORA_AVAILABLE:
        return

    for result in results:
        rule_id = result.get("rule_id")
        if not rule_id:
            continue
        try:
            aurora.execute("""
                INSERT INTO eval_outcomes
                    (case_id, rule_id, result, explanation, is_blocking)
                VALUES
                    (:case_id, :rule_id, :result, :explanation, :is_blocking)
                ON CONFLICT (case_id, rule_id) DO UPDATE
                SET result      = EXCLUDED.result,
                    explanation = EXCLUDED.explanation,
                    evaluated_at = NOW()
            """, [
                aurora.param("case_id",     case_id),
                aurora.param("rule_id",     rule_id),
                aurora.param("result",      result.get("result", "INCONCLUSIVE")),
                aurora.param("explanation", result.get("explanation", "")),
                aurora.param("is_blocking", result.get("is_blocking", True)),
            ])
        except Exception as e:
            logger.warning("Aurora eval_outcomes write failed (non-fatal): %s", e)


def write_case_summary_to_aurora(case_id: str, summary: dict):
    """Write case summary to Aurora case_summaries table."""
    if not AURORA_AVAILABLE:
        return

    try:
        aurora.execute("""
            INSERT INTO case_summaries
                (case_id, priority, complexity, recommendation,
                 supervisor_review, model_used, summary_json)
            VALUES
                (:case_id, :priority, :complexity, :recommendation,
                 :supervisor_review, :model_used, :summary_json::jsonb)
            ON CONFLICT (case_id) DO UPDATE
            SET priority          = EXCLUDED.priority,
                complexity        = EXCLUDED.complexity,
                recommendation    = EXCLUDED.recommendation,
                supervisor_review = EXCLUDED.supervisor_review,
                model_used        = EXCLUDED.model_used,
                summary_json      = EXCLUDED.summary_json,
                created_at        = NOW()
        """, [
            aurora.param("case_id",          case_id),
            aurora.param("priority",         summary.get("priority", "MEDIUM")),
            aurora.param("complexity",       summary.get("complexity", "MEDIUM")),
            aurora.param("recommendation",   summary.get("recommended_action", "")),
            aurora.param("supervisor_review",summary.get("supervisor_review_required", False)),
            aurora.param("model_used",       summary.get("model_used", "")),
            aurora.param("summary_json",     json.dumps(summary)),
        ])
    except Exception as e:
        logger.warning("Aurora case_summaries write failed (non-fatal): %s", e)
