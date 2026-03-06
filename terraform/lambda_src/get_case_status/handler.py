"""
GET /cases/{caseId}/status
Reads the single DynamoDB item for this case and maps its fields
to pipeline stage statuses for the caseworker portal.

DynamoDB item structure (from your agents):
{
  caseId:                  "COUNCILA-2026-121251"
  status:                  "READY_FOR_CASEWORKER_REVIEW"
  policyStatus:            "INCONCLUSIVE"
  priority:                "MEDIUM"
  requiresSupervisorReview: false
  caseSummary:             { ... }
  extractedData:           { ... }
  policyResult:            { ... }
  casePackS3Key:           "case_packs/COUNCILA-2026-121251/case_pack.json"
  createdAt:               "..."
  updatedAt:               "..."
}
"""

import json
import os
import boto3

dynamodb    = boto3.resource("dynamodb")
TABLE       = os.environ["DYNAMODB_TABLE"]
PACK_BUCKET = os.environ.get("CASE_PACK_BUCKET", "")

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,x-api-key",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
}

# Map your single status field value → which stages are complete
# Based on what your agents actually write to the status field
STATUS_STAGE_MAP = {
    # After intake Lambda completes
    "INTAKE_VALIDATED":             ["intake"],
    "INTAKE_COMPLETE":              ["intake"],

    # After Agent 1 — tech validation
    "DOCS_TECHNICALLY_VALIDATED":   ["intake", "agent1"],
    "TECH_VALIDATION_COMPLETE":     ["intake", "agent1"],

    # After Agent 2 — data extraction
    "DOCS_DATA_EXTRACTED":          ["intake", "agent1", "agent2"],
    "DATA_EXTRACTION_COMPLETE":     ["intake", "agent1", "agent2"],

    # After Agent 3 — policy evaluation
    "POLICY_EVALUATED":             ["intake", "agent1", "agent2", "agent3"],
    "POLICY_COMPLETE":              ["intake", "agent1", "agent2", "agent3"],
    "POLICY_PASSED":                ["intake", "agent1", "agent2", "agent3"],
    "INCONCLUSIVE":                 ["intake", "agent1", "agent2", "agent3"],

    # After Agent 4 — case summary (what you actually have)
    "READY_FOR_CASEWORKER_REVIEW":  ["intake", "agent1", "agent2", "agent3", "agent4"],
    "CASE_SUMMARY_COMPLETE":        ["intake", "agent1", "agent2", "agent3", "agent4"],

    # Caseworker decisions
    "APPROVED":                     ["intake", "agent1", "agent2", "agent3", "agent4", "review"],
    "DECLINED":                     ["intake", "agent1", "agent2", "agent3", "agent4", "review"],
    "ESCALATED":                    ["intake", "agent1", "agent2", "agent3", "agent4", "review"],
}

STAGE_ORDER = ["intake", "agent1", "agent2", "agent3", "agent4", "review"]


def build_stages(item):
    status     = item.get("status", "")
    updated_at = item.get("updatedAt") or item.get("createdAt")

    # Which stages are complete based on overall status
    complete_stages = STATUS_STAGE_MAP.get(status, [])

    stages = {}
    for stage in STAGE_ORDER:
        if stage in complete_stages:
            # Last complete stage is the active one, rest are done
            is_last = stage == complete_stages[-1]
            if status == "READY_FOR_CASEWORKER_REVIEW" and stage == "review":
                stages[stage] = {"status": "READY", "updatedAt": updated_at}
            elif is_last and stage != "review":
                stages[stage] = {"status": "COMPLETE", "updatedAt": updated_at}
            else:
                stages[stage] = {"status": "COMPLETE", "updatedAt": updated_at}
        else:
            stages[stage] = {"status": "PENDING", "updatedAt": None}

    # Mark review as READY if status is READY_FOR_CASEWORKER_REVIEW
    if status == "READY_FOR_CASEWORKER_REVIEW":
        stages["review"] = {"status": "READY", "updatedAt": updated_at}

    return stages


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    case_id     = path_params.get("caseId") or path_params.get("id", "")

    if not case_id:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "caseId required"})
        }

    try:
        table = dynamodb.Table(TABLE)

        # Try get_item first (your table uses caseId as the only key)
        response = table.get_item(Key={"caseId": case_id})
        item     = response.get("Item")

        if not item:
            # Fallback to query if table has a sort key
            from boto3.dynamodb.conditions import Key
            resp  = table.query(KeyConditionExpression=Key("caseId").eq(case_id))
            items = resp.get("Items", [])
            item  = items[0] if items else None

        if not item:
            return {
                "statusCode": 404,
                "headers": CORS_HEADERS,
                "body": json.dumps({"error": f"Case {case_id} not found"})
            }

        status = item.get("status", "UNKNOWN")
        stages = build_stages(item)

        # Check if case pack is available
        pack_s3_key    = item.get("casePackS3Key") or item.get("case_pack_s3_key")
        pack_available = bool(pack_s3_key)

        # If no explicit key, check S3
        if not pack_s3_key and PACK_BUCKET and status == "READY_FOR_CASEWORKER_REVIEW":
            s3 = boto3.client("s3")
            key = f"case_packs/{case_id}/case_pack.json"
            try:
                s3.head_object(Bucket=PACK_BUCKET, Key=key)
                pack_s3_key    = key
                pack_available = True
            except Exception:
                pass

        body = {
            "caseId":        case_id,
            "overallStatus": status,
            "priority":      item.get("priority", "MEDIUM"),
            "policyStatus":  item.get("policyStatus", ""),
            "requiresSupervisorReview": item.get("requiresSupervisorReview", False),
            "stages":        stages,
            "casePack": {
                "available": pack_available,
                "s3Key":     pack_s3_key,
            }
        }

        return {"statusCode": 200, "headers": CORS_HEADERS, "body": json.dumps(body)}

    except Exception as e:
        print(f"ERROR: {e}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e), "caseId": case_id})
        }
