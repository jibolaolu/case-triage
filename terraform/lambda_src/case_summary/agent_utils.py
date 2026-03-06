"""
lambda_src/shared/agent_utils.py

Shared utilities imported by all 4 agent handlers.
Place agent_utils.py in the SAME directory as handler.py when packaging each agent.

Provides:
  AuroraClient         — thin wrapper around RDS Data API
  update_status()      — update DynamoDB runtime state
  write_audit()        — append event to audit trail table (fixes activity tracking)
  get_policy_rules()   — fetch active rules from Aurora (replaces hardcoded dicts)
  write_extracted()    — persist extracted fields to Aurora
  write_eval_outcomes()— persist policy evaluation results to Aurora
  write_case_summary() — persist final case summary to Aurora
"""

import json
import os
import time
import boto3
import logging
from datetime import datetime, timezone
from decimal import Decimal

logger = logging.getLogger()

_region = os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2")

dynamodb = boto3.resource("dynamodb", region_name=_region)
rds      = boto3.client("rds-data",  region_name=_region)

DYNAMODB_TABLE     = os.environ.get("DYNAMODB_TABLE", "")
AUDIT_TRAIL_TABLE  = os.environ.get("AUDIT_TRAIL_TABLE", "")
AURORA_CLUSTER_ARN = os.environ.get("AURORA_CLUSTER_ARN", "")
AURORA_SECRET_ARN  = os.environ.get("AURORA_SECRET_ARN", "")
AURORA_DATABASE    = os.environ.get("AURORA_DATABASE", "case_triage")

AURORA_READY = bool(AURORA_CLUSTER_ARN and AURORA_SECRET_ARN)


# ── DecimalEncoder ─────────────────────────────────────────────────────────────

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


# ── DynamoDB helpers ───────────────────────────────────────────────────────────

def get_case(case_id: str) -> dict:
    """Load full case item from runtime state table."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    result = table.get_item(Key={"caseId": case_id})
    return result.get("Item", {})


def update_status(case_id: str, new_status: str, extra: dict = None):
    """Update the runtime status of a case in DynamoDB."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    now   = datetime.now(timezone.utc).isoformat()

    expr   = "SET #s = :status, updatedAt = :now"
    names  = {"#s": "status"}
    values = {":status": new_status, ":now": now}

    if extra:
        for k, v in extra.items():
            safe_k = k.replace("-", "_")
            expr  += f", {safe_k} = :{safe_k}"
            values[f":{safe_k}"] = v

    table.update_item(
        Key={"caseId": case_id},
        UpdateExpression=expr,
        ExpressionAttributeNames=names,
        ExpressionAttributeValues=values,
    )
    logger.info("DynamoDB status updated: %s → %s", case_id, new_status)


def write_audit(case_id: str, agent: str,
                from_status: str, to_status: str, details: dict = None):
    """
    Append an event to the case_audit_trail DynamoDB table.
    This is what makes agent activity visible and trackable.

    Query a full case history:
      aws dynamodb query \\
        --table-name case-triage-dev-case-audit-trail \\
        --key-condition-expression "caseId = :id" \\
        --expression-attribute-values '{":id": {"S": "CASE-ID"}}' \\
        --region eu-west-2
    """
    if not AUDIT_TRAIL_TABLE:
        logger.warning("AUDIT_TRAIL_TABLE env var not set — audit write skipped")
        return

    now = datetime.now(timezone.utc).isoformat()
    ttl = int(time.time()) + (7 * 365 * 24 * 3600)  # 7 years

    dynamodb.Table(AUDIT_TRAIL_TABLE).put_item(Item={
        "caseId":     case_id,
        "eventAt":    now,
        "agent":      agent,
        "fromStatus": from_status or "",
        "toStatus":   to_status,
        "details":    json.dumps(details or {}, cls=DecimalEncoder),
        "expiresAt":  ttl,
    })
    logger.info("Audit: [%s] %s → %s", agent, from_status, to_status)


# ── Aurora RDS Data API wrapper ────────────────────────────────────────────────

class AuroraClient:
    """RDS Data API wrapper with parameter helpers."""

    def _run(self, sql: str, params: list = None) -> dict:
        kwargs = {
            "resourceArn": AURORA_CLUSTER_ARN,
            "secretArn":   AURORA_SECRET_ARN,
            "database":    AURORA_DATABASE,
            "sql":         sql,
        }
        if params:
            kwargs["parameters"] = params
        return rds.execute_statement(**kwargs)

    def query(self, sql: str, params: list = None) -> list[dict]:
        resp    = self._run(sql, params)
        cols    = [c["name"] for c in resp.get("columnMetadata", [])]
        records = []
        for row in resp.get("records", []):
            record = {}
            for col, field in zip(cols, row):
                val = next(iter(field.values())) if field else None
                record[col] = None if field.get("isNull") else val
            records.append(record)
        return records

    def execute(self, sql: str, params: list = None):
        self._run(sql, params)

    @staticmethod
    def p(name: str, value) -> dict:
        """Build an RDS Data API typed parameter."""
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


# ── Aurora data writers (all non-fatal — Aurora is Phase 2, not critical path) -

def get_policy_rules(org_id: str, case_type: str) -> list[dict]:
    """
    Fetch active policy rules from Aurora.
    Returns [] if Aurora not ready — callers fall back to hardcoded rules.
    """
    if not AURORA_READY:
        return []
    try:
        rules = aurora.query("""
            SELECT pr.rule_id, pr.rule_name, pr.field_name,
                   pr.operator, pr.comparison_value::text,
                   pr.is_blocking, pr.description, pr.sort_order
            FROM policy_rules pr
            JOIN policies p ON pr.policy_id = p.policy_id
            WHERE p.org_id = :org_id
              AND p.case_type = :case_type
              AND p.status = 'active'
            ORDER BY pr.sort_order ASC
        """, [aurora.p("org_id", org_id), aurora.p("case_type", case_type)])
        logger.info("Aurora: loaded %d rules for %s/%s", len(rules), org_id, case_type)
        return rules
    except Exception as e:
        logger.warning("Aurora policy rules fetch failed (non-fatal): %s", e)
        return []


def write_case_to_aurora(case_id: str, org_id: str, case_type: str, policy_version: int):
    """Write authoritative case record. Idempotent (ON CONFLICT DO NOTHING)."""
    if not AURORA_READY:
        return
    try:
        aurora.execute("""
            INSERT INTO cases (case_id, organisation_id, case_type, policy_version)
            VALUES (:case_id, :org_id, :case_type, :pv)
            ON CONFLICT (case_id) DO NOTHING
        """, [aurora.p("case_id", case_id), aurora.p("org_id", org_id),
              aurora.p("case_type", case_type), aurora.p("pv", policy_version)])
    except Exception as e:
        logger.warning("Aurora case write failed (non-fatal): %s", e)


def write_extracted(case_id: str, fields: dict):
    """Write extracted fields to Aurora extracted_data table."""
    if not AURORA_READY:
        return
    try:
        for name, value in fields.items():
            aurora.execute("""
                INSERT INTO extracted_data (case_id, field_name, field_value, confidence)
                VALUES (:cid, :fn, :fv, 0.85)
                ON CONFLICT (case_id, field_name)
                DO UPDATE SET field_value = EXCLUDED.field_value, extracted_at = NOW()
            """, [aurora.p("cid", case_id),
                  aurora.p("fn", name),
                  aurora.p("fv", str(value) if value is not None else None)])
    except Exception as e:
        logger.warning("Aurora extracted_data write failed (non-fatal): %s", e)


def write_eval_outcomes(case_id: str, results: list[dict]):
    """Write policy evaluation rule results to Aurora eval_outcomes table."""
    if not AURORA_READY:
        return
    try:
        for r in results:
            rid = r.get("rule_id")
            if not rid:
                continue
            aurora.execute("""
                INSERT INTO eval_outcomes
                    (case_id, rule_id, result, explanation, is_blocking)
                VALUES (:cid, :rid::uuid, :res, :exp, :blk)
                ON CONFLICT (case_id, rule_id)
                DO UPDATE SET result = EXCLUDED.result, evaluated_at = NOW()
            """, [aurora.p("cid", case_id),
                  aurora.p("rid", rid),
                  aurora.p("res", r.get("status", "INCONCLUSIVE")),
                  aurora.p("exp", r.get("rationale", "")),
                  aurora.p("blk", r.get("blocking", True))])
    except Exception as e:
        logger.warning("Aurora eval_outcomes write failed (non-fatal): %s", e)


def write_case_summary_aurora(case_id: str, summary: dict):
    """Write final case summary to Aurora case_summaries table."""
    if not AURORA_READY:
        return
    try:
        rec = summary.get("recommendation", {})
        aurora.execute("""
            INSERT INTO case_summaries
                (case_id, priority, complexity, recommendation,
                 supervisor_review, model_used, summary_json)
            VALUES (:cid, :pri, :cmp, :rec, :sup, :mod, :js)
            ON CONFLICT (case_id)
            DO UPDATE SET priority = EXCLUDED.priority,
                          summary_json = EXCLUDED.summary_json,
                          created_at = NOW()
        """, [aurora.p("cid", case_id),
              aurora.p("pri", rec.get("priority_level", "MEDIUM")),
              aurora.p("cmp", rec.get("estimated_decision_complexity", "MODERATE")),
              aurora.p("rec", rec.get("suggested_next_action", "")),
              aurora.p("sup", rec.get("requires_supervisor_review", False)),
              aurora.p("mod", summary.get("model_used", "")),
              aurora.p("js",  summary)])
    except Exception as e:
        logger.warning("Aurora case_summaries write failed (non-fatal): %s", e)
