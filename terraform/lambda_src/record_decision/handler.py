"""
POST /cases/{caseId}/decision - Record caseworker decision.
Body: decision (approve|decline|escalate), justification, idempotencyKey (optional).
Updates DynamoDB, Aurora decisions/escalations, audit trail, EventBridge.
"""

import json
import os
import time
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
rds_data = boto3.client("rds-data")
events = boto3.client("events")

TABLE = os.environ["DYNAMODB_TABLE"]
AUDIT_TRAIL_TABLE = os.environ["AUDIT_TRAIL_TABLE"]
AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]
EVENTBRIDGE_BUS = os.environ["EVENTBRIDGE_BUS"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
}

DECISION_MAP = {"approve": "APPROVED", "decline": "DECLINED", "escalate": "ESCALATED"}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _rds_param(name: str, value) -> dict:
    if value is None:
        return {"name": name, "value": {"isNull": True}}
    if isinstance(value, bool):
        return {"name": name, "value": {"booleanValue": value}}
    if isinstance(value, int):
        return {"name": name, "value": {"longValue": value}}
    if isinstance(value, float):
        return {"name": name, "value": {"doubleValue": value}}
    return {"name": name, "value": {"stringValue": str(value)}}


def _rds_execute(sql: str, params: list = None):
    kwargs = {
        "resourceArn": AURORA_CLUSTER_ARN,
        "secretArn": AURORA_SECRET_ARN,
        "database": AURORA_DATABASE,
        "sql": sql,
    }
    if params:
        kwargs["parameters"] = params
    return rds_data.execute_statement(**kwargs)


def _get_decided_by(event) -> str:
    try:
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        if isinstance(claims, dict):
            return claims.get("sub") or claims.get("userId") or "anonymous"
        return "anonymous"
    except Exception:
        return "anonymous"


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    case_id = path_params.get("caseId") or path_params.get("id", "")

    if not case_id:
        return _response(400, {"error": "caseId required"})

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError as e:
        print(f"Invalid JSON body: {e}")
        return _response(400, {"error": "Invalid JSON body"})

    decision = (body.get("decision") or "").lower().strip()
    justification = (body.get("justification") or "").strip()

    if not decision:
        return _response(400, {"error": "decision is required"})
    if not justification:
        return _response(400, {"error": "justification is required"})
    if decision not in DECISION_MAP:
        return _response(400, {"error": f"decision must be one of: approve, decline, escalate"})

    new_status = DECISION_MAP[decision]
    decided_by = _get_decided_by(event)
    now = datetime.now(timezone.utc).isoformat()
    ttl = int(time.time()) + (7 * 365 * 24 * 3600)

    try:
        # 1. Update DynamoDB
        table = dynamodb.Table(TABLE)
        table.update_item(
            Key={"caseId": case_id},
            UpdateExpression="SET #s = :status, decidedAt = :now, decidedBy = :by, justification = :just",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":status": new_status,
                ":now": now,
                ":by": decided_by,
                ":just": justification,
            },
        )

        # 2. Aurora: decisions table (schema: outcome, notes, caseworker_id, decided_at)
        _rds_execute(
            """INSERT INTO decisions (case_id, outcome, notes, decided_at)
               VALUES (:cid, :outcome, :notes, :decided_at)""",
            [
                _rds_param("cid", case_id),
                _rds_param("outcome", new_status),
                _rds_param("notes", justification),
                _rds_param("decided_at", now),
            ],
        )

        # 3. If escalate: Aurora escalations table (raised_by allows NULL for anonymous)
        if decision == "escalate":
            raised_by_val = None if decided_by == "anonymous" else decided_by
            _rds_execute(
                """INSERT INTO escalations (case_id, reason, raised_by, created_at)
                   VALUES (:cid, :reason, :raised_by, :created_at)""",
                [
                    _rds_param("cid", case_id),
                    _rds_param("reason", justification),
                    _rds_param("raised_by", raised_by_val),
                    _rds_param("created_at", now),
                ],
            )

        # 4. DynamoDB audit trail
        audit_table = dynamodb.Table(AUDIT_TRAIL_TABLE)
        audit_table.put_item(Item={
            "caseId": case_id,
            "eventAt": now,
            "agent": "caseworker",
            "action": "DECISION_RECORDED",
            "details": json.dumps({"decision": decision, "justification": justification}),
            "expiresAt": ttl,
        })

        # 5. EventBridge
        events.put_events(Entries=[{
            "Source": "case.triage",
            "DetailType": "CASE_DECISION_RECORDED",
            "Detail": json.dumps({"caseId": case_id, "decision": decision, "justification": justification}),
            "EventBusName": EVENTBRIDGE_BUS,
        }])

        return _response(200, {"caseId": case_id, "status": new_status, "decidedAt": now})

    except Exception as e:
        print(f"ERROR recording decision for case {case_id}: {e}")
        return _response(500, {"error": str(e), "caseId": case_id})
