"""
GET /notifications - Get notifications for the current user.
Query param: unreadOnly (optional boolean)
Env: NOTIFICATIONS_TABLE
"""

import base64
import json
import os
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")

NOTIFICATIONS_TABLE = os.environ["NOTIFICATIONS_TABLE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,x-api-key",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _get_user_id(event):
    """Extract userId from authorizer claims sub or query param."""
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    if isinstance(claims, dict) and claims.get("sub"):
        return claims["sub"]
    params = event.get("queryStringParameters") or {}
    return params.get("userId", "")


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    user_id = _get_user_id(event)
    if not user_id:
        return _response(400, {"error": "userId required (from authorizer or query param userId)"})

    params = event.get("queryStringParameters") or {}
    unread_only = str(params.get("unreadOnly", "false")).lower() in ("true", "1", "yes")

    try:
        table = dynamodb.Table(NOTIFICATIONS_TABLE)
        response = table.query(
            KeyConditionExpression=Key("userId").eq(user_id),
            ScanIndexForward=False,
        )
        items = response.get("Items", [])

        if unread_only:
            items = [i for i in items if not i.get("read", False)]

        notifications = []
        for item in items:
            created_at = item.get("createdAt", "")
            user_id_val = item.get("userId", user_id)
            notif_id = item.get("id") or (
                base64.b64encode(f"{user_id_val}#{created_at}".encode()).decode() if created_at else ""
            )
            notifications.append({
                "id": notif_id,
                "type": item.get("type", ""),
                "title": item.get("title", ""),
                "message": item.get("message", ""),
                "read": item.get("read", False),
                "createdAt": created_at,
                "caseId": item.get("caseId", ""),
            })

        return _response(200, {"notifications": notifications})

    except Exception as e:
        print(f"ERROR: {e}")
        return _response(500, {"error": str(e)})
