"""
ApplicationFinalize Lambda — POST /applications/complete
Layer 2, Step 1C

Responsibilities:
1. Load case context from DynamoDB
2. Verify all required documents exist in S3
3. Update DynamoDB status → INTAKE_VALIDATED
4. Emit CASE_INTAKE_VALIDATED event to EventBridge custom bus
"""

import json
import os
import boto3
import logging
from decimal import Decimal
from datetime import datetime, timezone
from botocore.exceptions import ClientError


class DecimalEncoder(json.JSONEncoder):
    """DynamoDB returns Decimal for numbers — convert to int/float for JSON."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb    = boto3.resource("dynamodb")
s3_client   = boto3.client("s3")
events      = boto3.client("events")

DYNAMODB_TABLE    = os.environ["DYNAMODB_TABLE"]
DOCUMENTS_BUCKET  = os.environ["DOCUMENTS_BUCKET"]
EVENTBRIDGE_BUS   = os.environ["EVENTBRIDGE_BUS"]

REQUIRED_DOC_TYPES = [
    "id_proof",
    "bank_statement_jan",
    "bank_statement_dec",
    "bank_statement_nov",
    "tenancy_agreement",
]


def lambda_handler(event, context):
    logger.info("ApplicationFinalize invoked")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    case_id = body.get("caseId")
    if not case_id:
        return _response(400, {"error": "caseId is required"})

    # ── 1. Load case from DynamoDB ────────────────────────────────────────────
    table = dynamodb.Table(DYNAMODB_TABLE)
    try:
        result = table.get_item(Key={"caseId": case_id})
        case = result.get("Item")
        if not case:
            return _response(404, {"error": f"Case {case_id} not found"})
    except ClientError as e:
        logger.error("DynamoDB read failed: %s", e)
        return _response(500, {"error": "Failed to load case"})

    # Guard: only finalise if awaiting documents
    if case["status"] != "AWAITING_DOCUMENTS":
        return _response(409, {
            "error": f"Case is in status '{case['status']}' — cannot finalise"
        })

    org_id        = case["orgId"]
    case_type     = case["caseType"]
    policy_version = case.get("policyVersion", 1)

    # ── 2. Verify all documents exist in S3 ───────────────────────────────────
    missing_docs = []
    for doc_type in REQUIRED_DOC_TYPES:
        s3_key = f"{org_id}/{case_type}/{case_id}/documents/{doc_type}.pdf"
        try:
            s3_client.head_object(Bucket=DOCUMENTS_BUCKET, Key=s3_key)
        except ClientError as e:
            if e.response["Error"]["Code"] in ("404", "NoSuchKey"):
                missing_docs.append(doc_type)
            else:
                logger.error("S3 head_object error for %s: %s", doc_type, e)
                return _response(500, {"error": f"Failed to verify document: {doc_type}"})

    if missing_docs:
        return _response(422, {
            "error":       "Missing required documents",
            "missingDocs": missing_docs
        })

    # ── 3. Update DynamoDB → INTAKE_VALIDATED (+ optional applicant details from intake) ──
    now = datetime.now(timezone.utc).isoformat()
    optional = {
        "applicantName": body.get("applicantName"),
        "applicantEmail": body.get("applicantEmail"),
        "dob": body.get("dob") or body.get("applicantDob") or body.get("dateOfBirth"),
        "phone": body.get("phone") or body.get("applicantPhone"),
        "niNumber": body.get("niNumber") or body.get("ni_number"),
    }
    set_parts = ["#s = :status", "updatedAt = :now"]
    expr_names = {"#s": "status"}
    expr_values = {":status": "INTAKE_VALIDATED", ":now": now, ":expected": "AWAITING_DOCUMENTS"}
    for key, val in optional.items():
        if val is not None and str(val).strip():
            expr_names[f"#_{key}"] = key
            set_parts.append(f"#_{key} = :{key}")
            expr_values[f":{key}"] = str(val).strip()
    try:
        table.update_item(
            Key={"caseId": case_id},
            UpdateExpression="SET " + ", ".join(set_parts),
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
            ConditionExpression="#s = :expected"
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(409, {"error": "Case status changed during processing — retry"})
        logger.error("DynamoDB update failed: %s", e)
        return _response(500, {"error": "Failed to update case status"})

    # ── 4. Emit CASE_INTAKE_VALIDATED to EventBridge ──────────────────────────
    event_payload = {
        "caseId":        case_id,
        "orgId":         org_id,
        "caseType":      case_type,
        "policyVersion": policy_version,
        "status":        "INTAKE_VALIDATED",
        "validatedAt":   now,
    }

    try:
        events.put_events(Entries=[{
            "Source":       "case.intake",
            "DetailType":   "CASE_INTAKE_VALIDATED",
            "Detail":       json.dumps(event_payload, cls=DecimalEncoder),
            "EventBusName": EVENTBRIDGE_BUS,
        }])
        logger.info("CASE_INTAKE_VALIDATED emitted for case %s", case_id)
    except ClientError as e:
        # Log but don't fail — DynamoDB is already updated
        # EventBridge DLQ + retry will recover this
        logger.error("EventBridge emit failed for %s: %s", case_id, e)

    logger.info("Case %s finalised. Status: INTAKE_VALIDATED", case_id)

    return _response(200, {
        "caseId":  case_id,
        "status":  "INTAKE_VALIDATED",
        "message": "Application received and validated. Processing will begin shortly."
    })


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":              "application/json",
            "X-Content-Type-Options":    "nosniff",
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
        },
        "body": json.dumps(body)
    }
