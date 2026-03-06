"""
PUT /cases/{caseId}/assign - Assign a case to a caseworker.
Body: assignedTo (user ID), assignedToName.
Updates DynamoDB, Aurora cases table, audit trail.
"""

import json
import os
import time
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
rds_data = boto3.client("rds-data")

TABLE = os.environ["DYNAMODB_TABLE"]
AUDIT_TRAIL_TABLE = os.environ["AUDIT_TRAIL_TABLE"]
AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
}


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

    assigned_to = (body.get("assignedTo") or "").strip()
    assigned_to_name = (body.get("assignedToName") or "").strip()

    if not assigned_to:
        return _response(400, {"error": "assignedTo is required"})
    if not assigned_to_name:
        return _response(400, {"error": "assignedToName is required"})

    now = datetime.now(timezone.utc).isoformat()
    ttl = int(time.time()) + (7 * 365 * 24 * 3600)

    try:
        # 1. Update DynamoDB
        table = dynamodb.Table(TABLE)
        table.update_item(
            Key={"caseId": case_id},
            UpdateExpression="SET assignedTo = :to, assignedToName = :name, updatedAt = :now",
            ExpressionAttributeValues={
                ":to": assigned_to,
                ":name": assigned_to_name,
                ":now": now,
            },
        )

        # 2. Aurora: UPDATE cases SET assigned_to, assigned_to_name
        _rds_execute(
            """UPDATE cases SET assigned_to = :val, assigned_to_name = :name, updated_at = :now WHERE case_id = :cid""",
            [
                _rds_param("val", assigned_to),
                _rds_param("name", assigned_to_name),
                _rds_param("now", now),
                _rds_param("cid", case_id),
            ],
        )

        # 3. DynamoDB audit trail
        audit_table = dynamodb.Table(AUDIT_TRAIL_TABLE)
        audit_table.put_item(Item={
            "caseId": case_id,
            "eventAt": now,
            "agent": "caseworker",
            "action": "CASE_ASSIGNED",
            "details": json.dumps({"assignedTo": assigned_to, "assignedToName": assigned_to_name}),
            "expiresAt": ttl,
        })

        return _response(200, {"caseId": case_id, "assignedTo": assigned_to, "assignedToName": assigned_to_name})

    except Exception as e:
        print(f"ERROR assigning case {case_id}: {e}")
        return _response(500, {"error": str(e), "caseId": case_id})
