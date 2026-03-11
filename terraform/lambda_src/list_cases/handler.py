"""
GET /cases - Lists cases from DynamoDB case_runtime_state table.
Query params: status (optional GSI filter), limit (default 20, max 100),
nextToken (base64 ExclusiveStartKey), assignedTo (optional filter).
"""

import base64
import json
import os
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource("dynamodb")

TABLE = os.environ["DYNAMODB_TABLE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    try:
        params = event.get("queryStringParameters") or {}
        status = params.get("status")
        limit = min(int(params.get("limit", 20)), 100)
        next_token = params.get("nextToken")
        assigned_to = params.get("assignedTo")

        table = dynamodb.Table(TABLE)
        exclusive_start_key = None
        if next_token:
            try:
                exclusive_start_key = json.loads(base64.b64decode(next_token).decode("utf-8"))
            except Exception as e:
                print(f"Invalid nextToken: {e}")
                return _response(400, {"error": "Invalid nextToken"})

        if status:
            # Query status-index GSI (partition key: status)
            kwargs = {
                "IndexName": "status-index",
                "KeyConditionExpression": Key("status").eq(status),
                "Limit": limit,
            }
            if exclusive_start_key:
                kwargs["ExclusiveStartKey"] = exclusive_start_key
            if assigned_to:
                kwargs["FilterExpression"] = Attr("assignedTo").eq(assigned_to)
            response = table.query(**kwargs)
        else:
            # Scan when no status filter
            kwargs = {"Limit": limit}
            if exclusive_start_key:
                kwargs["ExclusiveStartKey"] = exclusive_start_key
            if assigned_to:
                kwargs["FilterExpression"] = Attr("assignedTo").eq(assigned_to)
            response = table.scan(**kwargs)

        items = response.get("Items", [])
        last_key = response.get("LastEvaluatedKey")

        cases = []
        for item in items:
            cases.append({
                "caseId": item.get("caseId", ""),
                "applicantName": item.get("applicantName", ""),
                "applicationType": item.get("applicationType") or item.get("caseType", ""),
                "status": item.get("status", ""),
                "priority": item.get("priority", ""),
                "assignedTo": item.get("assignedTo", ""),
                "assignedToName": item.get("assignedToName", ""),
                "updatedAt": item.get("updatedAt", ""),
                "aiConfidence": item.get("aiConfidence"),
                "createdAt": item.get("createdAt", ""),
            })

        # Sort newest first so new cases appear at the top (without deleting old ones)
        cases.sort(key=lambda c: (c.get("updatedAt") or c.get("createdAt") or ""), reverse=True)

        next_token_out = None
        if last_key:
            next_token_out = base64.b64encode(json.dumps(last_key).encode("utf-8")).decode("utf-8")

        return _response(200, {"cases": cases, "nextToken": next_token_out})

    except ValueError as e:
        print(f"Validation error: {e}")
        return _response(400, {"error": str(e)})
    except Exception as e:
        print(f"ERROR: {e}")
        return _response(500, {"error": str(e)})
